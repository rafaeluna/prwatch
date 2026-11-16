import AppKit
import SwiftUI

/// A floating panel that sizes its height to the list and keeps its top edge where you left it.
/// It shows the focused look while the pointer is over it or it has the keyboard.
@MainActor
final class PanelController {
    static let defaultWidth: CGFloat = 340
    let panel = FloatingPanel()
    private let settings: AppSettings
    private let monitor: Monitor
    private var contentView: PanelContentView!
    private var isPointerInside = false

    init(monitor: Monitor, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.monitor = monitor
        let hostingView = NSHostingView(rootView: PullRequestListView(
            monitor: monitor,
            settings: settings,
            openSettings: openSettings,
            minimize: { [weak self] in self?.minimize() },
            onContentHeightChange: { [weak self] height in self?.fit(contentHeight: height) }
        ))
        hostingView.sizingOptions = []
        contentView = PanelContentView(content: hostingView)
        contentView.onPointerInsideChange = { [weak self] isInside in
            self?.isPointerInside = isInside
            self?.applyLook()
        }
        panel.contentView = contentView
        placePanel()
        trackKeyStatus()
        observeChanges { [weak self] in self?.applyLook() }
    }

    func show() {
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
        } else {
            panel.orderFrontRegardless()
        }
        monitor.refreshIfStale()
    }

    /// Sends the panel into the Dock; clicking it there or the app icon brings it back.
    func minimize() {
        panel.miniaturize(nil)
    }

    func toggle() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    private func applyLook() {
        let look = settings.look(isFocused: isPointerInside || panel.isKeyWindow)
        contentView.apply(look, texture: settings.texture, textureIntensity: settings.textureIntensity)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = look.opacity
        }
        // Around Liquid Glass the window shadow comes out square and shows as an outline. The glass has
        // its own depth, so it goes without; blur and solid keep their rounded shadow.
        panel.hasShadow = look.background != .glass
        panel.invalidateShadow()
    }

    private func fit(contentHeight: CGFloat) {
        let screenHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let height = min(ceil(contentHeight), screenHeight * 0.8)
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func placePanel() {
        let frameName = "PrwatchPanel"
        if !panel.setFrameUsingName(frameName) {
            let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let height: CGFloat = 200
            panel.setFrame(
                NSRect(x: visibleFrame.maxX - 3 * Self.defaultWidth - 60, y: visibleFrame.maxY - 20 - height, width: Self.defaultWidth, height: height),
                display: false
            )
        }
        panel.setFrameAutosaveName(frameName)
    }

    private func trackKeyStatus() {
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyLook() }
            }
        }
    }
}

final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelController.defaultWidth, height: 200),
            styleMask: [.borderless, .nonactivatingPanel, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        minSize = NSSize(width: 260, height: 60)
        maxSize = NSSize(width: 700, height: 4000)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
