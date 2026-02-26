import Foundation

enum CapabilityStatus: String, Codable, CaseIterable, Sendable {
    case available
    case degraded
    case blocked
    case unsupported
    case unknown

    var severityRank: Int {
        switch self {
        case .available: return 0
        case .unknown: return 1
        case .degraded: return 2
        case .unsupported: return 3
        case .blocked: return 4
        }
    }
}

struct CapabilityState: Identifiable, Codable, Sendable {
    let key: String
    let status: CapabilityStatus
    let reasonCode: String?
    let message: String
    let remediationSteps: [String]

    var id: String { key }
}

enum MissionControlCheckStatus: String, Codable, Sendable {
    case pass
    case warning
    case unknown
}

struct MissionControlCheck: Identifiable, Codable, Sendable {
    let key: String
    let expected: String
    let actual: String?
    let status: MissionControlCheckStatus
    let message: String

    var id: String { key }
}

struct SystemProfile: Codable, Sendable {
    let macOSVersion: String
    let macOSBuild: String?
    let arch: String
    let yabaiVersion: String?
    let skhdVersion: String?
    let detectedAt: Date
}

enum HealthBadgeLevel: String, Codable, Sendable {
    case healthy
    case warning
    case degraded
    case blocked

    var symbolName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .degraded: return "minus.circle.fill"
        case .blocked: return "xmark.circle.fill"
        }
    }

    var title: String {
        rawValue.capitalized
    }
}

struct DoctorSnapshot: Codable, Sendable {
    let generatedAt: Date
    let systemProfile: SystemProfile
    let capabilities: [CapabilityState]
    let missionControlChecks: [MissionControlCheck]
    let compatibilityWarnings: [String]
    let healthBadge: HealthBadgeLevel
}

enum CommandErrorType: String, Codable, Sendable {
    case launchFailure
    case timeout
    case nonZeroExit
    case none
}

struct CommandResult: Codable, Sendable {
    let command: String
    let startedAt: Date
    let endedAt: Date
    let exitStatus: Int32?
    let stdout: String
    let stderr: String
    let errorType: CommandErrorType

    var durationMs: Int {
        Int(endedAt.timeIntervalSince(startedAt) * 1000)
    }

    var isSuccess: Bool {
        exitStatus == 0 && errorType == .none
    }
}

struct CommandLogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let command: String
    let startedAt: Date
    let endedAt: Date
    let durationMs: Int
    let exitStatus: Int32?
    let stdoutSnippet: String
    let stderrSnippet: String
    let errorType: CommandErrorType
}

struct DiagnosticsReport: Codable, Sendable {
    let generatedAt: Date
    let systemProfile: SystemProfile
    let health: DoctorSnapshot
    let capabilities: [CapabilityState]
    let recentCommands: [CommandLogEntry]
}

enum StateSourceQuality: String, Codable, Sendable {
    case yabai
    case fallback
    case stale
}

struct DisplayState: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let focused: Bool
    let windowCount: Int
    let source: StateSourceQuality
    let lastUpdatedAt: Date
}

struct SpaceState: Identifiable, Codable, Sendable {
    let index: Int
    let label: String?
    let displayId: Int
    let focused: Bool
    let visible: Bool
    let layout: String?
    let windowCount: Int
    let source: StateSourceQuality
    let lastUpdatedAt: Date

    var id: Int { index }
}

struct WindowState: Identifiable, Codable, Sendable {
    let id: Int
    let app: String
    let space: Int
    let display: Int
    let floating: Bool
    let title: String
    let focused: Bool
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let source: StateSourceQuality
    let lastUpdatedAt: Date
}

struct FallbackDisplayCount: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let windowCount: Int
    let source: StateSourceQuality
    let lastUpdatedAt: Date
}

struct LiveStateSnapshot: Codable, Sendable {
    let displays: [DisplayState]
    let spaces: [SpaceState]
    let windows: [WindowState]
    let fallbackDisplays: [FallbackDisplayCount]
    let source: StateSourceQuality
    let lastUpdatedAt: Date
    let degraded: Bool
    let degradedReason: String?
    let yabaiWindowTotal: Int?
    let fallbackWindowTotal: Int?
    let consecutiveMismatchSamples: Int
    let consecutiveHealthySamples: Int
    let lastErrorMessage: String?
}

struct ShortcutEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let combo: String
    let command: String
    let category: String
    let sourceLine: Int
    let sourceFile: String
    let warning: String?
}

struct ConfigBackupInfo: Identifiable, Codable, Sendable {
    let id: UUID
    let path: String
    let createdAt: Date
    let sizeBytes: Int64
}

enum SetupCheckState: String, Codable, Sendable {
    case installed
    case missing
    case warning
    case unknown
}

struct SetupCheckItem: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let state: SetupCheckState
    let detail: String
}

struct SetupBootstrapSnapshot: Codable, Sendable {
    let generatedAt: Date
    let items: [SetupCheckItem]
    let brewPrefix: String?
}

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
    var neverTileApps: [String]
    var alwaysTileApps: [String]

    static let `default` = ManagedWindowBehaviorPolicy(
        manualTilingModeEnabled: false,
        hoverFocusMode: .off,
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
