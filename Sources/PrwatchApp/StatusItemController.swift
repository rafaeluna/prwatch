import AppKit
import PrwatchCore

/// The menu bar counts the pull requests waiting on you, in orange when one of yours has comments.
/// Click toggles the panel; right-click offers Refresh, Settings and Quit. It can be turned off in Settings.
@MainActor
final class StatusItemController: NSObject {
    private let togglePanel: () -> Void
    private let openSettings: () -> Void
    private let refresh: () -> Void
    private var item: NSStatusItem?
    private var pullRequests: [PullRequest] = []

    init(togglePanel: @escaping () -> Void, openSettings: @escaping () -> Void, refresh: @escaping () -> Void) {
        self.togglePanel = togglePanel
        self.openSettings = openSettings
        self.refresh = refresh
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible, item == nil {
            item = makeItem()
            show(pullRequests)
        }
        if !isVisible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func show(_ pullRequests: [PullRequest]) {
        self.pullRequests = pullRequests
        guard let button = item?.button else { return }
        let withComments = pullRequests.count(.comments)
        let toReview = pullRequests.count(.review)
        let approved = pullRequests.count(.approved)
        let count = withComments + toReview + approved
        button.title = count > 0 ? " \(count)" : ""
        button.contentTintColor = withComments > 0 ? .systemOrange : nil
        button.toolTip = "\(withComments) with comments, \(toReview) to review, \(approved) approved, \(pullRequests.waiting.count) waiting on others"
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "PRwatch")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    @objc private func clicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp, let button = item?.button else {
            togglePanel()
            return
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PRwatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func refreshFromMenu() {
        refresh()
    }
}
