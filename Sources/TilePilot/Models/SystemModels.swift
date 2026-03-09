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

enum SystemCheckStatus: String, Sendable {
    case good
    case notice
    case warning
    case error

    var severityRank: Int {
        switch self {
        case .good: return 0
        case .notice: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    var symbolName: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .notice: return "questionmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

enum SystemCheckAction: String, Sendable, Hashable {
    case installDependencies
    case installCLT
    case startYabai
    case startSkhd
    case enableStartAtLogon
    case openLoginItemsSettings
    case openAccessibilitySettings
    case requestAccessibilityAccess
    case fixScriptingAddition
    case openMissionControlSettings
    case openMissionControlKeyboardShortcuts
    case restartYabai
    case restartSkhd
    case recheck

    var label: String {
        switch self {
        case .installDependencies: return "Install"
        case .installCLT: return "Install CLT"
        case .startYabai: return "Start yabai"
        case .startSkhd: return "Start skhd"
        case .enableStartAtLogon: return "Enable"
        case .openLoginItemsSettings: return "Login Items"
        case .openAccessibilitySettings: return "Open Settings"
        case .requestAccessibilityAccess: return "Request Access"
        case .fixScriptingAddition: return "Fix"
        case .openMissionControlSettings: return "Mission Control"
        case .openMissionControlKeyboardShortcuts: return "Keyboard Shortcuts"
        case .restartYabai: return "Restart yabai"
        case .restartSkhd: return "Restart skhd"
        case .recheck: return "Recheck"
        }
    }
}

struct SystemCheckRow: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let status: SystemCheckStatus
    let actions: [SystemCheckAction]
}

enum SystemPanelSection: String, Sendable {
    case essentials
    case files
    case managedConfig
    case diagnostics
}
