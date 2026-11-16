import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let monitor = Monitor()
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private lazy var panelController = PanelController(monitor: monitor, settings: settings) { [weak self] in
        self?.settingsWindow.show()
    }
    private lazy var statusItem = StatusItemController(
        togglePanel: { [weak self] in self?.panelController.toggle() },
        openSettings: { [weak self] in self?.settingsWindow.show() },
        refresh: { [weak self] in self?.monitor.refresh() }
    )
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = makeMainMenu()
        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            statusItem.show(monitor.pullRequests)
        }
        monitor.start()
        hotKey = GlobalHotKey { [weak self] in
            self?.panelController.toggle()
        }
        observeChanges { [weak self] in self?.applyHotKeyAndStatusItem() }
        panelController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return false
    }

    private func applyHotKeyAndStatusItem() {
        if settings.isRecordingHotKey {
            hotKey?.unregister()  // So pressing the current shortcut records it instead of firing it
        } else if let combo = settings.hotKey {
            hotKey?.register(combo)
        } else {
            hotKey?.unregister()
        }
        statusItem.setVisible(settings.showsMenuBarIcon)
    }

    @objc private func openSettingsFromMenu() {
        settingsWindow.show()
    }

    @objc private func minimizePanelFromMenu() {
        panelController.minimize()
    }

    @objc private func refreshFromMenu() {
        monitor.refresh()
    }

    /// The app sits in the Dock, so its menu bar shows while it's active.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide PRwatch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit PRwatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r").target = self

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(minimizePanelFromMenu), keyEquivalent: "m").target = self
        NSApp.windowsMenu = windowMenu

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu, viewMenu, windowMenu] {
            let menuItem = NSMenuItem()
            menuItem.submenu = submenu
            mainMenu.addItem(menuItem)
        }
        return mainMenu
    }
}

@MainActor
func renderSnapshot(to url: URL) {
    let monitor = Monitor()
    monitor.refreshNow()
    let content = PullRequestListContent(
        pullRequests: monitor.pullRequests,
        now: monitor.now,
        lastUpdated: monitor.lastUpdated,
        problem: monitor.problem,
        isFetching: false
    )
    .environment(\.listStyle, AppSettings().listStyle)
    .frame(width: PanelController.defaultWidth)
    .background(Color(white: 0.14))
    .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 2
    guard let image = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: url)
}
