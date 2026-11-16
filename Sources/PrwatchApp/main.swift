import AppKit

MainActor.assumeIsolated {
    // `--render <file.png>` draws the current list to an image and quits, for screenshots.
    let arguments = CommandLine.arguments
    if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
        renderSnapshot(to: URL(fileURLWithPath: arguments[index + 1]))
        exit(0)
    }

    let appDelegate = AppDelegate()
    NSApplication.shared.delegate = appDelegate
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.run()
}
