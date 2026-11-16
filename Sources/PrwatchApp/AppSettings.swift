import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

enum PanelBackground: String, CaseIterable, Identifiable, Codable {
    case glass, blur, solid

    var id: Self { self }

    var label: String {
        switch self {
        case .glass: "Liquid Glass"
        case .blur: "Blur"
        case .solid: "Solid"
        }
    }
}

enum GlassStyle: String, CaseIterable, Identifiable, Codable {
    case regular, clear

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

enum TexturePattern: String, CaseIterable, Identifiable {
    case none, grain, dots, grid, scanlines

    var id: Self { self }
    var label: String { rawValue.capitalized }
}

/// How the panel looks in one state. Pointed at and not pointed at each get their own.
struct PanelLook: Codable, Equatable {
    var background: PanelBackground
    var glassStyle: GlassStyle
    var darkness: Double
    var tint: TintColor
    var tintStrength: Double
    var opacity: Double
    var customBlurRadius: Double?

    static let systemBlurRadius = 30.0

    var blurRadius: Double {
        get { customBlurRadius ?? Self.systemBlurRadius }
        set { customBlurRadius = newValue }
    }
}

struct TintColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let defaultTint = TintColor(red: 0.35, green: 0.55, blue: 1)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: NSColor) {
        let srgbColor = color.usingColorSpace(.sRGB) ?? color
        red = srgbColor.redComponent
        green = srgbColor.greenComponent
        blue = srgbColor.blueComponent
    }

    var color: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}

enum LookState {
    case focused, unfocused
}

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlagsRawValue: UInt
    var keyLabel: String

    static let defaultCombo = HotKeyCombo(
        keyCode: UInt32(kVK_ANSI_P),
        modifierFlagsRawValue: NSEvent.ModifierFlags([.control, .option, .command]).rawValue,
        keyLabel: "P"
    )

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var displayString: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifierSymbols = symbols.filter { flag, _ in modifierFlags.contains(flag) }.map(\.1).joined()
        return modifierSymbols + keyLabel
    }
}

/// The same settings Daylist has, minus the ones only a checklist needs. "Focused" here means the
/// pointer is over the panel (or it has the keyboard), since you mostly look at this panel, not type in it.
@MainActor
@Observable
final class AppSettings {
    var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: "fontSize") } }
    var usesMonospacedFont: Bool { didSet { UserDefaults.standard.set(usesMonospacedFont, forKey: "usesMonospacedFont") } }
    var focusedLook: PanelLook { didSet { store(focusedLook, forKey: "focusedLook") } }
    var unfocusedLook: PanelLook { didSet { store(unfocusedLook, forKey: "unfocusedLook") } }
    var changesLookWhenUnfocused: Bool { didSet { UserDefaults.standard.set(changesLookWhenUnfocused, forKey: "changesLookWhenUnfocused") } }
    var texture: TexturePattern { didSet { UserDefaults.standard.set(texture.rawValue, forKey: "texture") } }
    var textureIntensity: Double { didSet { UserDefaults.standard.set(textureIntensity, forKey: "textureIntensity") } }
    var showsMenuBarIcon: Bool { didSet { UserDefaults.standard.set(showsMenuBarIcon, forKey: "showsMenuBarIcon") } }
    var hotKey: HotKeyCombo? {
        // Empty data marks a cleared shortcut; a missing key means "use the default".
        didSet { UserDefaults.standard.set(hotKey.flatMap { combo in try? JSONEncoder().encode(combo) } ?? Data(), forKey: "hotKey") }
    }
    var isRecordingHotKey = false
    var previewedLook: LookState?  // Set while Settings is open, so the panel shows the look being edited

    /// Until you change them here, the look settings come from Daylist, so the two panels match.
    private static let daylistDefaults = UserDefaults(suiteName: "io.github.rafaeluna.daylist")

    init() {
        let defaults = UserDefaults.standard
        func stored<Value>(_ key: String) -> Value? {
            defaults.object(forKey: key) as? Value ?? Self.daylistDefaults?.object(forKey: key) as? Value
        }

        fontSize = defaults.object(forKey: "fontSize") as? Double ?? ListStyle.defaultBaseSize
        usesMonospacedFont = stored("usesMonospacedFont") ?? false
        focusedLook = Self.storedLook(forKey: "focusedLook") ?? PanelLook(
            background: .glass,
            glassStyle: .regular,
            darkness: 0.35,
            tint: .defaultTint,
            tintStrength: 0,
            opacity: 1
        )
        unfocusedLook = Self.storedLook(forKey: "unfocusedLook") ?? PanelLook(
            background: .glass,
            glassStyle: .regular,
            darkness: 0.35,
            tint: .defaultTint,
            tintStrength: 0,
            opacity: 0.85
        )
        changesLookWhenUnfocused = stored("changesLookWhenUnfocused") ?? true
        texture = (stored("texture") as String?).flatMap(TexturePattern.init) ?? .none
        textureIntensity = stored("textureIntensity") ?? 0.6
        showsMenuBarIcon = defaults.object(forKey: "showsMenuBarIcon") as? Bool ?? true
        if let storedHotKey = defaults.data(forKey: "hotKey") {
            hotKey = try? JSONDecoder().decode(HotKeyCombo.self, from: storedHotKey)
        } else {
            hotKey = .defaultCombo
        }
    }

    var listStyle: ListStyle {
        ListStyle(baseSize: fontSize, isMonospaced: usesMonospacedFont)
    }

    func look(isFocused: Bool) -> PanelLook {
        showsFocusedLook(isFocused: isFocused) ? focusedLook : unfocusedLook
    }

    private static func storedLook(forKey key: String) -> PanelLook? {
        guard let data = UserDefaults.standard.data(forKey: key) ?? daylistDefaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PanelLook.self, from: data)
    }

    private func store(_ look: PanelLook, forKey key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(look), forKey: key)
    }

    private func showsFocusedLook(isFocused: Bool) -> Bool {
        guard changesLookWhenUnfocused else { return true }
        if let previewedLook { return previewedLook == .focused }
        return isFocused
    }
}

/// Text size and face for the list. Sizes in the views are written as they look at the default size.
struct ListStyle {
    static let defaultBaseSize: Double = 13

    var baseSize = Self.defaultBaseSize
    var isMonospaced = false

    func font(_ size: Double, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight, design: isMonospaced ? .monospaced : .default)
    }

    func scaled(_ size: Double) -> Double {
        (size * baseSize / Self.defaultBaseSize).rounded()
    }
}

private struct ListStyleKey: EnvironmentKey {
    static let defaultValue = ListStyle()
}

extension EnvironmentValues {
    var listStyle: ListStyle {
        get { self[ListStyleKey.self] }
        set { self[ListStyleKey.self] = newValue }
    }
}
