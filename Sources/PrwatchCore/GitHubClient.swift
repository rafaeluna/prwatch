import Foundation

/// Asks GitHub through the `gh` command, so there is no token to set up or store: whoever `gh` is
/// logged in as is whose pull requests you see.
public struct GitHubClient: Sendable {
    public struct Failure: Error, Equatable {
        public var message: String
    }

    private static let timeout: TimeInterval = 30

    public init() {}

    public func fetchPullRequests() throws -> [PullRequest] {
        guard let gh = Self.findGH() else {
            throw Failure(message: "The gh command isn't installed. Run: brew install gh")
        }
        let (output, errorOutput) = try run(gh, arguments: ["api", "graphql", "-f", "query=\(GitHubResponse.query)"])
        do {
            // When GitHub answers with data and errors both, gh exits non-zero but the data is still good.
            return try GitHubResponse.pullRequests(from: output)
        } catch let failure as GitHubResponse.Failure {
            throw Failure(message: failure.message)
        } catch {
            throw Failure(message: Self.readable(errorOutput))
        }
    }

    private func run(_ executable: URL, arguments: [String]) throws -> (output: Data, errorOutput: String) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        do {
            try process.run()
        } catch {
            throw Failure(message: "Couldn't run gh: \(error.localizedDescription)")
        }
        // Without a network gh can wait a long time. Stopping it ends the read below.
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) {
            if process.isRunning { process.terminate() }
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (output, errorOutput)
    }

    /// An app opened from the Dock doesn't get your shell's PATH, so the usual install places come first.
    private static func findGH() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let usualPlaces = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/opt/local/bin", "/usr/bin"]
        let pathPlaces = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (usualPlaces + pathPlaces)
            .map { URL(fileURLWithPath: $0).appending(path: "gh") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func readable(_ errorOutput: String) -> String {
        let firstLine = errorOutput.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        if errorOutput.contains("gh auth login") {
            return "gh isn't logged in. Run: gh auth login"
        }
        if firstLine.isEmpty {
            return "GitHub didn't answer"
        }
        return firstLine
    }
}
