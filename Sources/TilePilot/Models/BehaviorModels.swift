import Foundation

enum HoverFocusMode: String, Codable, CaseIterable, Sendable {
    case off
    case autofocus
    case autoraise

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .autofocus: return "Auto Focus"
        case .autoraise: return "Auto Raise"
        }
    }
}

struct ManagedWindowBehaviorPolicy: Codable, Sendable, Equatable {
    var manualTilingModeEnabled: Bool
    var hoverFocusMode: HoverFocusMode
    var mouseFollowsFocusEnabled: Bool
    var neverTileApps: [String]
    var alwaysTileApps: [String]

    static let `default` = ManagedWindowBehaviorPolicy(
        manualTilingModeEnabled: false,
        hoverFocusMode: .off,
        mouseFollowsFocusEnabled: false,
        neverTileApps: [],
        alwaysTileApps: []
    )
}

struct YabaiConfigDocumentState: Sendable {
    let filePath: String
    let fileExists: Bool
    let fullContent: String
    let managedSectionBody: String
    let hasManagedSection: Bool
    let backups: [ConfigBackupInfo]
    let policy: ManagedWindowBehaviorPolicy
}

struct YabaiConfigSaveResult: Sendable {
    let filePath: String
    let backups: [ConfigBackupInfo]
    let previousBackup: ConfigBackupInfo?
    let wasInsert: Bool
}

struct YabaiConfigRestoreResult: Sendable {
    let filePath: String
    let backups: [ConfigBackupInfo]
    let restoredBackup: ConfigBackupInfo
    let preRestoreBackup: ConfigBackupInfo?
}

enum AppTilingBehavior: String, Codable, CaseIterable, Sendable {
    case useDefault
    case neverTile
    case alwaysTile

    var displayName: String {
        switch self {
        case .useDefault: return "Default"
        case .neverTile: return "Never Tile"
        case .alwaysTile: return "Always Tile"
        }
    }
}

enum AppForegroundPolicy: String, Codable, CaseIterable, Sendable {
    case useDefault
    case keepFrontWhenFloating

    var displayName: String {
        switch self {
        case .useDefault: return "Default"
        case .keepFrontWhenFloating: return "Keep on Top"
        }
    }
}
