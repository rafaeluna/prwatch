import Foundation
import PrwatchCore

let usage = """
    prwatch: list the pull requests that are waiting on you.

      prwatch           Print the list once
      prwatch --watch   Redraw it every two minutes (Ctrl-C to stop)
    """

let arguments = CommandLine.arguments.dropFirst()
if arguments.contains("--help") || arguments.contains("-h") {
    print(usage)
    exit(0)
}

let isWatching = arguments.contains("--watch") || arguments.contains("-w")
let usesColor = isatty(STDOUT_FILENO) == 1
let client = GitHubClient()

func paint(_ text: String, _ code: String) -> String {
    usesColor ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
}

func report(_ pullRequests: [PullRequest], now: Date) -> String {
    if pullRequests.isEmpty {
        return "No open pull requests."
    }
    var lines: [String] = []
    if pullRequests.actionable.isEmpty {
        lines.append("Nothing is waiting on you.")
    }
    for pullRequest in pullRequests {
        let label = pullRequest.attention.label(elapsed: Elapsed.short(now.timeIntervalSince(pullRequest.since)))
        let place = "\(pullRequest.repository) #\(pullRequest.number)"
        // Pull requests waiting on others get one dim line: there's nothing to do about them yet.
        guard pullRequest.attention.isActionable else {
            lines.append(paint("· \(pullRequest.shortTitle)  \(place)  \(label)", "2"))
            continue
        }
        let (dot, color) = switch pullRequest.attention {
        case .comments: ("!", "33")
        case .approved: ("✓", "32")
        default: ("●", "34")
        }
        lines.append("\(paint(dot, color)) \(pullRequest.shortTitle)  \(paint(label, color))")
        var detail = "  " + paint(place, "2")
        if pullRequest.attention == .review {
            detail += "  \(pullRequest.author)"
            if let size = pullRequest.size {
                detail += paint("  \(size.text)", "2")
            }
        }
        lines.append(detail)
        for comment in pullRequest.comments {
            lines.append("    ↳ \(paint(comment.author, "1")) \(comment.text)")
        }
        lines.append("  " + paint(pullRequest.urlToOpen.absoluteString, "2"))
    }
    return lines.joined(separator: "\n")
}

repeat {
    let output: String
    do {
        output = report(try client.fetchPullRequests(), now: .now)
    } catch let failure as GitHubClient.Failure {
        output = paint(failure.message, "31")
    }
    if isWatching {
        print("\u{1B}[H\u{1B}[2J", terminator: "")
    }
    print(output)
    if isWatching {
        Thread.sleep(forTimeInterval: 120)
    }
} while isWatching
