import CoreGraphics
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
    let frameX: Double
    let frameY: Double
    let frameW: Double
    let frameH: Double
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
    let pid: Int
    let app: String
    let space: Int
    let display: Int
    let frameX: Double
    let frameY: Double
    let frameW: Double
    let frameH: Double
    let floating: Bool
    let hasAXReference: Bool
    let canMove: Bool
    let canResize: Bool
    let title: String
    let focused: Bool
    let isVisible: Bool
    let isMinimized: Bool
    let isHidden: Bool
    let source: StateSourceQuality
    let lastUpdatedAt: Date

    var isRuntimeManageable: Bool {
        // Some apps expose windows that can be tiled/floated and moved, but report can-resize=false.
        // Treat those as controllable for runtime actions.
        hasAXReference && canMove
    }
}

enum WindowBadgeVisibilityMode: String, Codable, CaseIterable, Sendable {
    case focusedAndHovered
    case alwaysOn
    case focusedOnly
}

struct WindowBadgeState: Identifiable, Sendable, Equatable {
    let windowID: Int
    let pid: Int
    let app: String
    let title: String
    let isFloating: Bool
    let isFocused: Bool
    let isRuntimeManageable: Bool
    let frameX: Double
    let frameY: Double
    let frameW: Double
    let frameH: Double

    var id: Int { windowID }

    var frame: CGRect {
        CGRect(x: frameX, y: frameY, width: frameW, height: frameH)
    }
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

struct OverviewDisplayPreview: Identifiable, Sendable {
    let id: Int
    let name: String
    let focused: Bool
    let aspectRatio: Double
    let frameW: Double
    let frameH: Double
    let desktops: [OverviewDesktopPreview]
}

struct OverviewDesktopPreview: Identifiable, Sendable {
    let id: String
    let displayID: Int
    let desktopIndex: Int
    let focused: Bool
    let visible: Bool
    let windows: [OverviewWindowPreview]
}

struct OverviewWindowPreview: Identifiable, Sendable {
    let id: Int
    let app: String
    let title: String
    let floating: Bool
    let runtimeManageable: Bool
    let focused: Bool
    let visible: Bool
    let normalizedX: Double
    let normalizedY: Double
    let normalizedW: Double
    let normalizedH: Double
}

struct ShortcutEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let combo: String
    let command: String
    let category: String
    let sourceLine: Int
    let sourceFile: String
    let warning: String?

    var stableKey: String {
        "\(combo)\n\(command)"
    }
}

enum DirectionalShortcutGroup: String, CaseIterable, Codable, Sendable {
    case focusWindow
    case moveWindow
    case resizeWindow
    case swapWindow

    var title: String {
        switch self {
        case .focusWindow: return "Focus Window (Direction Keys)"
        case .moveWindow: return "Move Window in Layout (Direction Keys)"
        case .resizeWindow: return "Resize Window (Direction Keys)"
        case .swapWindow: return "Swap Window (Direction Keys)"
        }
    }

    var menuTitle: String {
        switch self {
        case .focusWindow: return "Focus (IJKL)"
        case .moveWindow: return "Move Window (IJKL)"
        case .resizeWindow: return "Resize Window (IJKL)"
        case .swapWindow: return "Swap Window (IJKL)"
        }
    }
}

enum DirectionalShortcutDirection: String, CaseIterable, Codable, Sendable {
    case up
    case left
    case down
    case right

    var sortRank: Int {
        switch self {
        case .up: return 0
        case .left: return 1
        case .down: return 2
        case .right: return 3
        }
    }

    var label: String {
        switch self {
        case .up: return "Up"
        case .left: return "Left"
        case .down: return "Down"
        case .right: return "Right"
        }
    }

    var arrow: String {
        switch self {
        case .up: return "↑"
        case .left: return "←"
        case .down: return "↓"
        case .right: return "→"
        }
    }
}

struct DirectionalShortcutBinding: Identifiable, Sendable {
    let group: DirectionalShortcutGroup
    let direction: DirectionalShortcutDirection
    let entry: ShortcutEntry

    var id: String {
        "\(group.rawValue)-\(direction.rawValue)-\(entry.stableKey)"
    }
}

enum UnifiedControlGroup: String, CaseIterable, Codable, Sendable {
    case desktops
    case windowPlacement
    case tilingLayout
    case windowSize
    case helpersScripts
    case apps
    case focus
    case displays
    case automation
    case other
    case experimental

    var title: String {
        switch self {
        case .desktops: return "Desktops"
        case .windowPlacement: return "Window Placement"
        case .tilingLayout: return "Tiling & Layout"
        case .windowSize: return "Window Size"
        case .helpersScripts: return "Helpers & Scripts"
        case .apps: return "Apps"
        case .focus: return "Focus"
        case .displays: return "Displays"
        case .automation: return "Automation"
        case .other: return "Other"
        case .experimental: return "Desktop Move (Experimental)"
        }
    }

    var sortRank: Int {
        switch self {
        case .desktops: return 0
        case .windowPlacement: return 1
        case .tilingLayout: return 2
        case .windowSize: return 3
        case .helpersScripts: return 4
        case .apps: return 5
        case .focus: return 6
        case .displays: return 7
        case .automation: return 8
        case .other: return 98
        case .experimental: return 99
        }
    }
}

struct UnifiedControlRow: Identifiable, Sendable {
    let id: String
    let group: UnifiedControlGroup
    let title: String
    let description: String
    let shortcutEntry: ShortcutEntry?
    let actionID: TilePilotActionID?
    let secondaryActionIDs: [TilePilotActionID]
    let isExperimental: Bool
    let disabledReason: String?
    let intentKey: String
    let featureID: FeatureControlID?
}

struct FeatureControlID: RawRepresentable, Hashable, Codable, Sendable, Identifiable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }

    var id: String { rawValue }
}

enum FeatureExecutionBackend: String, Codable, Sendable {
    case shortcutCommand
    case tilePilotAction
    case scriptPath
}

enum FeatureCapabilityGate: String, Codable, Sendable {
    case none
    case yabaiRuntime
    case scriptingAddition
}

enum FeatureShortcutBindingState: Sendable, Equatable {
    case assigned(combo: String)
    case missing(defaultCombo: String?)
    case conflict(combo: String, conflictingFeatureTitle: String, suggestions: [String])
    case disabled(reason: String)
}

enum FeatureRunSource: String, Sendable {
    case shortcutsUI
    case statusMenu
}

struct FeatureControlRow: Identifiable, Sendable {
    let id: String
    let featureID: FeatureControlID?
    let group: UnifiedControlGroup
    let title: String
    let description: String
    let backend: FeatureExecutionBackend
    let capabilityGate: FeatureCapabilityGate
    let shortcutEntry: ShortcutEntry?
    let actionID: TilePilotActionID?
    let preferredCommand: String?
    let assignedCombo: String?
    let defaultCombo: String?
    let bindingState: FeatureShortcutBindingState
    let isExperimental: Bool
    let disabledReason: String?
}

enum ShortcutsDisplayItem: Identifiable, Sendable {
    case featureRow(FeatureControlRow)
    case directionalFamily(group: DirectionalShortcutGroup, bindings: [DirectionalShortcutBinding])
    case desktopJumpFamily(entries: [ShortcutEntry])
    case desktopMoveFamily(entries: [ShortcutEntry])

    var id: String {
        switch self {
        case .featureRow(let row):
            if let featureID = row.featureID {
                return "feature.\(featureID.rawValue)"
            }
            if let stableKey = row.shortcutEntry?.stableKey {
                return "shortcut.\(stableKey)"
            }
            if let actionID = row.actionID {
                return "action.\(actionID.rawValue)"
            }
            return "row.\(row.id)"
        case .directionalFamily(let group, _):
            return "directional.\(group.rawValue)"
        case .desktopJumpFamily:
            return "family.desktop-jump"
        case .desktopMoveFamily:
            return "family.desktop-move"
        }
    }
}

enum PinnedShortcutContextItem: Identifiable, Sendable {
    case feature(FeatureControlRow)
    case directional(group: DirectionalShortcutGroup, bindings: [DirectionalShortcutBinding])
    case shortcut(ShortcutEntry)

    var id: String {
        switch self {
        case .feature(let row):
            if let featureID = row.featureID {
                return "feature.\(featureID.rawValue)"
            }
            if let stableKey = row.shortcutEntry?.stableKey {
                return "shortcut.\(stableKey)"
            }
            return "feature-row.\(row.id)"
        case .directional(let group, _):
            return "directional.\(group.rawValue)"
        case .shortcut(let entry):
            return "shortcut.\(entry.stableKey)"
        }
    }
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
        case .keepFrontWhenFloating: return "Keep on Top (When Floating)"
        }
    }
}

enum ReleaseDefaultsApplyMode: String, Codable, Sendable {
    case firstInstall
    case manualReset
}

struct ReleaseDefaultsUserState: Codable, Sendable {
    let pinnedFeatureControlIDs: [String]
    let pinnedDirectionalGroupIDs: [String]
    let shortcutsCustomOrderIDs: [String]
    let showWindowBadgeOverlay: Bool
    let showWindowOutlineOverlay: Bool
    let raiseOnFloatToggleEnabled: Bool
    let appForegroundPolicyByName: [String: AppForegroundPolicy]

    init(
        pinnedFeatureControlIDs: [String],
        pinnedDirectionalGroupIDs: [String],
        shortcutsCustomOrderIDs: [String] = [],
        showWindowBadgeOverlay: Bool,
        showWindowOutlineOverlay: Bool,
        raiseOnFloatToggleEnabled: Bool,
        appForegroundPolicyByName: [String: AppForegroundPolicy]
    ) {
        self.pinnedFeatureControlIDs = pinnedFeatureControlIDs
        self.pinnedDirectionalGroupIDs = pinnedDirectionalGroupIDs
        self.shortcutsCustomOrderIDs = shortcutsCustomOrderIDs
        self.showWindowBadgeOverlay = showWindowBadgeOverlay
        self.showWindowOutlineOverlay = showWindowOutlineOverlay
        self.raiseOnFloatToggleEnabled = raiseOnFloatToggleEnabled
        self.appForegroundPolicyByName = appForegroundPolicyByName
    }

    private enum CodingKeys: String, CodingKey {
        case pinnedFeatureControlIDs
        case pinnedDirectionalGroupIDs
        case shortcutsCustomOrderIDs
        case showWindowBadgeOverlay
        case showWindowOutlineOverlay
        case raiseOnFloatToggleEnabled
        case appForegroundPolicyByName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pinnedFeatureControlIDs = try container.decode([String].self, forKey: .pinnedFeatureControlIDs)
        pinnedDirectionalGroupIDs = try container.decode([String].self, forKey: .pinnedDirectionalGroupIDs)
        shortcutsCustomOrderIDs = try container.decodeIfPresent([String].self, forKey: .shortcutsCustomOrderIDs) ?? []
        showWindowBadgeOverlay = try container.decode(Bool.self, forKey: .showWindowBadgeOverlay)
        showWindowOutlineOverlay = try container.decode(Bool.self, forKey: .showWindowOutlineOverlay)
        raiseOnFloatToggleEnabled = try container.decode(Bool.self, forKey: .raiseOnFloatToggleEnabled)
        appForegroundPolicyByName = try container.decode([String: AppForegroundPolicy].self, forKey: .appForegroundPolicyByName)
    }
}

struct ReleaseDefaultsConfigState: Codable, Sendable {
    let managedSkhdSectionBody: String
    let windowBehaviorPolicy: ManagedWindowBehaviorPolicy
}

struct ReleaseDefaultsProfile: Codable, Sendable {
    let profileVersion: String
    let userState: ReleaseDefaultsUserState
    let configState: ReleaseDefaultsConfigState
}

enum ReleaseDefaultsStatus: Sendable, Equatable {
    case upToDate(version: String)
    case updateAvailable(currentVersion: String, lastAppliedVersion: String)
    case neverApplied(currentVersion: String)

    var summaryText: String {
        switch self {
        case .upToDate(let version):
            return "Release defaults \(version) are applied."
        case .updateAvailable(let currentVersion, let lastAppliedVersion):
            return "New release defaults available (\(lastAppliedVersion) -> \(currentVersion))."
        case .neverApplied(let currentVersion):
            return "Release defaults \(currentVersion) have not been applied yet."
        }
    }

    var currentVersion: String {
        switch self {
        case .upToDate(let version):
            return version
        case .updateAvailable(let currentVersion, _):
            return currentVersion
        case .neverApplied(let currentVersion):
            return currentVersion
        }
    }
}

struct EditorTarget: Equatable, Sendable {
    let path: String
    let line: Int?
}

enum EditableFileKind: String, Codable, CaseIterable, Sendable {
    case yabairc
    case skhdrc
    case script
    case other

    var displayName: String {
        switch self {
        case .yabairc: return "yabairc"
        case .skhdrc: return "skhdrc"
        case .script: return "script"
        case .other: return "file"
        }
    }
}

struct EditableConfigFile: Identifiable, Codable, Sendable, Hashable {
    let path: String
    let displayName: String
    let kind: EditableFileKind
    let exists: Bool
    let isDiscovered: Bool

    var id: String { path }
}

struct EditableFileDocumentState: Sendable {
    let file: EditableConfigFile
    let content: String
    let backups: [ConfigBackupInfo]
}

struct EditableFileSaveResult: Sendable {
    let file: EditableConfigFile
    let backups: [ConfigBackupInfo]
    let previousBackup: ConfigBackupInfo?
}

struct EditableFileRestoreResult: Sendable {
    let file: EditableConfigFile
    let backups: [ConfigBackupInfo]
    let restoredBackup: ConfigBackupInfo
    let preRestoreBackup: ConfigBackupInfo?
}
