import AppKit
import Foundation

enum DesktopScrubModifier: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case shift
    case control
    case option
    case command

    static let defaultSelection: [DesktopScrubModifier] = [.shift, .control, .option]
    static let minimumSelectionCount = 2

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shift: return "Shift"
        case .control: return "Control"
        case .option: return "Option"
        case .command: return "Command"
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }

    var chipLabel: String {
        "\(symbol) \(displayName)"
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .shift: return .shift
        case .control: return .control
        case .option: return .option
        case .command: return .command
        }
    }

    static func normalize(_ modifiers: [DesktopScrubModifier]) -> [DesktopScrubModifier] {
        allCases.filter { modifiers.contains($0) }
    }

    static func loadFromUserDefaults(rawValues: [String]?) -> [DesktopScrubModifier] {
        let parsed = normalize((rawValues ?? []).compactMap(Self.init(rawValue:)))
        return parsed.count >= minimumSelectionCount ? parsed : defaultSelection
    }

    static func flags(for modifiers: [DesktopScrubModifier]) -> NSEvent.ModifierFlags {
        normalize(modifiers).reduce(into: NSEvent.ModifierFlags()) { result, modifier in
            result.insert(modifier.modifierFlag)
        }
    }

    static func from(flags: NSEvent.ModifierFlags) -> [DesktopScrubModifier] {
        allCases.filter { flags.contains($0.modifierFlag) }
    }

    static func symbolsText(for modifiers: [DesktopScrubModifier]) -> String {
        let normalized = normalize(modifiers)
        guard !normalized.isEmpty else { return "None" }
        return normalized.map(\.symbol).joined(separator: " ")
    }

    static func wordsText(for modifiers: [DesktopScrubModifier]) -> String {
        let normalized = normalize(modifiers)
        guard !normalized.isEmpty else { return "no trigger keys" }
        return normalized.map(\.displayName).joined(separator: " + ")
    }
}
