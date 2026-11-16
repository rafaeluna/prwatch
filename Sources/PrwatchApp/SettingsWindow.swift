import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings

    private lazy var window: NSWindow = {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
        window.title = "PRwatch Settings"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        previewLooks(whileShowing: window)
        return window
    }()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// While Settings is in front the panel shows the look being edited, starting with the pointed-at one.
    /// Leaving the app or closing Settings hands it back. The color picker taking key status doesn't.
    private func previewLooks(whileShowing window: NSWindow) {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [settings] _ in
            MainActor.assumeIsolated { settings.previewedLook = settings.previewedLook ?? .focused }
        }
        notificationCenter.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [settings] _ in
            MainActor.assumeIsolated { settings.previewedLook = nil }
        }
        notificationCenter.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [settings] _ in
            MainActor.assumeIsolated { settings.previewedLook = nil }
        }
    }
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                LookEditor(look: $settings.focusedLook)
            } header: {
                Text("Look")
            } footer: {
                Text("Starts out matching your Daylist look until you change it here.")
                    .foregroundStyle(.secondary)
            }

            Section("When the pointer is elsewhere") {
                Toggle("Use a different look", isOn: $settings.changesLookWhenUnfocused)
                if settings.changesLookWhenUnfocused {
                    LookEditor(look: $settings.unfocusedLook)
                }
            }

            Section("Texture and text") {
                Picker("Texture", selection: $settings.texture) {
                    ForEach(TexturePattern.allCases) { pattern in
                        Text(pattern.label).tag(pattern)
                    }
                }
                if settings.texture != .none {
                    Slider(value: $settings.textureIntensity, in: 0.1...1) {
                        Text("Texture strength")
                    }
                }
                Toggle("Monospaced font", isOn: $settings.usesMonospacedFont)
                Stepper(value: $settings.fontSize, in: 10...20, step: 1) {
                    Text("Text size \(Int(settings.fontSize)) pt")
                }
            }

            Section {
                LabeledContent("Show or hide shortcut") {
                    HotKeyRecorder(settings: settings)
                }
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(.red)
                }
                Toggle("Show menu bar icon", isOn: $settings.showsMenuBarIcon)
            } header: {
                Text("Behavior")
            } footer: {
                Text("Without the menu bar icon, the shortcut or opening PRwatch again brings the panel back, and the gear in its header opens Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 680)
        .onChange(of: settings.focusedLook) { settings.previewedLook = .focused }
        .onChange(of: settings.unfocusedLook) { settings.previewedLook = .unfocused }
        .onChange(of: settings.changesLookWhenUnfocused) { settings.previewedLook = .unfocused }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchesAtLogin
        } set: { isOn in
            do {
                if isOn {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
            }
            launchesAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct LookEditor: View {
    @Binding var look: PanelLook

    var body: some View {
        Picker("Background", selection: $look.background) {
            ForEach(PanelBackground.allCases) { background in
                Text(background.label).tag(background)
            }
        }
        if look.background == .glass {
            Picker("Glass", selection: $look.glassStyle) {
                ForEach(GlassStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
        if look.background == .blur {
            Slider(value: $look.blurRadius, in: 0...60) {
                Text("Blur")
            }
        }
        if look.background != .solid {
            Slider(value: $look.darkness, in: 0...0.9) {
                Text("Darkness")
            }
        }
        ColorPicker("Tint", selection: tintColor, supportsOpacity: false)
        Slider(value: $look.tintStrength, in: 0...0.8) {
            Text("Tint strength")
        }
        Slider(value: $look.opacity, in: 0.3...1) {
            Text("Opacity")
        }
    }

    private var tintColor: Binding<Color> {
        Binding {
            Color(nsColor: look.tint.color)
        } set: { newColor in
            look.tint = TintColor(NSColor(newColor))
            if look.tintStrength == 0 {
                look.tintStrength = 0.3  // Picking a color at zero strength would show no change at all
            }
        }
    }
}

struct HotKeyRecorder: View {
    @Bindable var settings: AppSettings
    @State private var keyMonitor: Any?

    var body: some View {
        HStack {
            Button(buttonTitle) {
                if settings.isRecordingHotKey {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            if settings.hotKey != nil && !settings.isRecordingHotKey {
                Button("Clear") { settings.hotKey = nil }
            }
        }
    }

    private var buttonTitle: String {
        if settings.isRecordingHotKey { return "Press a shortcut" }
        return settings.hotKey?.displayString ?? "Record shortcut"
    }

    private func startRecording() {
        settings.isRecordingHotKey = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    stopRecording()
                    return nil
                }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                guard !modifiers.subtracting(.shift).isEmpty else {
                    NSSound.beep()  // A global shortcut needs ⌘, ⌥ or ⌃, or it would swallow normal typing
                    return nil
                }
                settings.hotKey = HotKeyCombo(
                    keyCode: UInt32(event.keyCode),
                    modifierFlagsRawValue: modifiers.rawValue,
                    keyLabel: keyLabel(for: event)
                )
                stopRecording()
                return nil
            }
        }
    }

    private func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        settings.isRecordingHotKey = false
    }

    private func keyLabel(for event: NSEvent) -> String {
        let namedKeys = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→"]
        if let name = namedKeys[Int(event.keyCode)] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
