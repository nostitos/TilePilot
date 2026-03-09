import CoreGraphics
import Foundation

enum StateSourceQuality: String, Codable, Sendable {
    case yabai
    case fallback
    case stale
}

struct DisplayState: Identifiable, Codable, Sendable, Equatable {
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

struct SpaceState: Identifiable, Codable, Sendable, Equatable {
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

struct WindowState: Identifiable, Codable, Sendable, Equatable {
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

struct FallbackDisplayCount: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let name: String
    let windowCount: Int
    let source: StateSourceQuality
    let lastUpdatedAt: Date
}

struct LiveStateSnapshot: Codable, Sendable, Equatable {
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

struct OverviewDisplayPreview: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let focused: Bool
    let aspectRatio: Double
    let frameW: Double
    let frameH: Double
    let desktops: [OverviewDesktopPreview]
}

struct OverviewDesktopPreview: Identifiable, Sendable, Equatable {
    let id: String
    let displayID: Int
    let desktopIndex: Int
    let focused: Bool
    let visible: Bool
    let tilingEnabled: Bool
    let windows: [OverviewWindowPreview]
}

struct OverviewWindowPreview: Identifiable, Sendable, Equatable {
    let id: Int
    let app: String
    let title: String
    let desktopIndex: Int
    let floating: Bool
    let runtimeManageable: Bool
    let focused: Bool
    let visible: Bool
    let normalizedX: Double
    let normalizedY: Double
    let normalizedW: Double
    let normalizedH: Double
}

struct OverviewDisplaySection: Identifiable, Sendable, Equatable {
    let id: Int
    let display: DisplayState
    let visibleWindowCount: Int
    let totalWindowCount: Int
    let spaces: [OverviewSpaceSection]
}

struct OverviewSpaceSection: Identifiable, Sendable, Equatable {
    let id: Int
    let space: SpaceState
    let tilingEnabled: Bool
    let visibleWindowCount: Int
    let totalWindowCount: Int
    let windows: [WindowState]
}

struct RuntimeDiagnostics: Sendable, Equatable {
    var liveStateRefreshCount: Int = 0
    var liveStatePublishedCount: Int = 0
    var liveStateUnchangedPollCount: Int = 0
    var overviewCacheRebuildCount: Int = 0
    var shortcutsCacheRebuildCount: Int = 0
    var keepOnTopEnforcementPassCount: Int = 0
    var miniMapHoverUpdateCount: Int = 0
    var overlayPanelUpdateCount: Int = 0
    var runtimeActivityMode: String = "Idle"
    var currentPollingIntervalSeconds: Double = 0
    var currentKeepOnTopIntervalSeconds: Double = 0
    var performanceMode: String = "Full"
    var performanceModeDetail: String = ""
    var recentLiveStateRefreshCount: Int = 0
    var recentLiveStatePublishedCount: Int = 0
    var recentLiveStateUnchangedPollCount: Int = 0
    var recentOverviewCacheRebuildCount: Int = 0
    var recentShortcutsCacheRebuildCount: Int = 0
    var recentKeepOnTopEnforcementPassCount: Int = 0
    var recentOverlayPanelUpdateCount: Int = 0
    var dominantBurstSource: String = "Idle"
}
