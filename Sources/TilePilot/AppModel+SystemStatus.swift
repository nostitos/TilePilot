import AppKit
import Foundation

@MainActor
extension AppModel {
    enum RuntimeActivityMode: String {
        case idle
        case overview
        case overlays
        case keepOnTop
        case mixed

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .overview: return "Overview"
            case .overlays: return "Overlays"
            case .keepOnTop: return "Keep-on-top"
            case .mixed: return "Mixed"
            }
        }

        var includesKeepOnTopWork: Bool {
            switch self {
            case .keepOnTop, .mixed:
                return true
            case .idle, .overview, .overlays:
                return false
            }
        }
    }

    var healthBadgeSymbol: String {
        doctorSnapshot?.healthBadge.symbolName ?? "questionmark.circle"
    }

    var menuBarHealthBadgeSymbol: String {
        if shouldUseNeutralSetupMenuBar {
            return "circle.dashed"
        }
        return menuBarVisualBadgeLevel?.symbolName ?? "questionmark.circle"
    }

    var healthBadgeTitle: String {
        doctorSnapshot?.healthBadge.title ?? "Unknown"
    }

    var menuBarStatusLine: String {
        if doctorSnapshot == nil {
            return "Starting..."
        }
        if shouldSoftenInitialBlockedStatus {
            guard let snapshot = doctorSnapshot else { return "Setup Needed" }
            return "Setup Needed · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
        }
        if shouldUseNeutralSetupMenuBar, let snapshot = doctorSnapshot {
            let summary = primaryMenuBarSummary() ?? "Not Set Up Yet"
            return "\(summary) · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
        }
        if shouldDowngradeBlockedToSetupNeededInMenuBar, let snapshot = doctorSnapshot {
            let summary = primaryMenuBarSummary() ?? "Setup Needed"
            return "\(summary) · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
        }
        guard let snapshot = doctorSnapshot else { return "Starting..." }
        let summary = primaryMenuBarSummary() ?? snapshot.healthBadge.title
        return "\(summary) · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
    }

    var statusLine: String {
        guard let snapshot = doctorSnapshot else { return "Setup check has not run yet" }
        return "\(snapshot.healthBadge.title) · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
    }

    var nowStatusLine: String {
        guard let snapshot = liveStateSnapshot else { return "No live state yet" }
        let source = snapshot.source.rawValue.capitalized
        return "\(source) · \(snapshot.lastUpdatedAt.formatted(date: .omitted, time: .standard))"
    }

    var runtimeActivityMode: RuntimeActivityMode {
        let tilePilotWindowVisible = hasVisibleTilePilotWindow
        let overviewVisible = tilePilotWindowVisible && currentVisibleTab == .now
        let overlaysActive = hasActiveOverlayTargets
        let keepOnTopActive = hasActiveKeepOnTopWindows

        let activeCount = [overviewVisible, overlaysActive, keepOnTopActive].filter { $0 }.count
        switch activeCount {
        case 0:
            return .idle
        case 1:
            if keepOnTopActive { return .keepOnTop }
            if overlaysActive { return .overlays }
            return .overview
        default:
            return .mixed
        }
    }

    func currentPollingIntervalSeconds() -> Double {
        switch runtimeActivityMode {
        case .overview, .overlays, .keepOnTop, .mixed:
            let baseInterval = overlayRefreshPolicy == .reduced
                ? max(performanceForegroundPollingSeconds, 2.5)
                : performanceForegroundPollingSeconds
            let keepOnTopInterval = currentKeepOnTopEnforcementIntervalSeconds()
            if performanceFastLiveRefreshEnabled {
                let fastInterval = min(baseInterval, 0.8)
                return keepOnTopInterval > 0 ? min(fastInterval, keepOnTopInterval) : fastInterval
            }
            return keepOnTopInterval > 0 ? min(baseInterval, keepOnTopInterval) : baseInterval
        case .idle:
            return max(10.0, performanceBackgroundPollingSeconds)
        }
    }

    var menuBarVisualBadgeLevel: HealthBadgeLevel? {
        guard let snapshot = doctorSnapshot else { return nil }
        if shouldUseNeutralSetupMenuBar {
            return nil
        }
        if shouldSoftenInitialBlockedStatus {
            return .warning
        }
        if shouldDowngradeBlockedToSetupNeededInMenuBar {
            return .warning
        }
        return snapshot.healthBadge
    }

    var hasObservedScriptingAdditionRuntimeFailure: Bool {
        commandLogs.prefix(100).contains { entry in
            let haystack = (entry.stderrSnippet + " " + entry.stdoutSnippet).lowercased()
            return haystack.contains("scripting-addition")
        }
    }

    private var shouldSoftenInitialBlockedStatus: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        return snapshot.healthBadge == .blocked && !hasAcknowledgedInitialStatus
    }

    private var shouldDowngradeBlockedToSetupNeededInMenuBar: Bool {
        guard let snapshot = doctorSnapshot, snapshot.healthBadge == .blocked else { return false }

        let blockedKeys = Set(snapshot.capabilities.filter { $0.status == .blocked }.map(\.key))
        if blockedKeys.isEmpty {
            return false
        }

        let commonSetupBlockedKeys: Set<String> = ["yabai-binary", "skhd-binary", "yabai-query"]
        guard blockedKeys.isSubset(of: commonSetupBlockedKeys) else {
            return false
        }

        if let bootstrapSnapshot {
            let hasMissingInstallDeps = bootstrapSnapshot.items.contains {
                ["homebrew", "yabai-binary", "skhd-binary"].contains($0.id) && $0.state == .missing
            }
            if hasMissingInstallDeps {
                return true
            }
        }

        return blockedKeys == Set(["yabai-query"])
    }

    private var shouldUseNeutralSetupMenuBar: Bool {
        if let bootstrapSnapshot {
            let setupMissingIDs: Set<String> = ["xcode-clt", "homebrew", "yabai-binary", "skhd-binary"]
            let hasSetupMissing = bootstrapSnapshot.items.contains { setupMissingIDs.contains($0.id) && $0.state == .missing }
            if hasSetupMissing {
                return true
            }
        }

        guard let snapshot = doctorSnapshot else { return false }
        let failing = snapshot.capabilities.filter { $0.status != .available }
        if failing.isEmpty { return false }

        let allSetupish = failing.allSatisfy { capability in
            ["yabai-binary", "skhd-binary", "yabai-daemon", "skhd-daemon", "yabai-query"].contains(capability.key)
        }
        return allSetupish && liveStateSnapshot == nil
    }

    private func primaryMenuBarSummary() -> String? {
        if windowBehaviorPolicyDraft.mouseFollowsFocusEnabled {
            return "Cursor follows focus is on"
        }
        if windowBehaviorPolicyDraft.hoverFocusMode != .off {
            return "Hover focus is on"
        }
        if !windowBehaviorPolicyDraft.manualTilingModeEnabled, yabaiConfigHasManagedSection {
            return "Manual tiling off"
        }

        if let bootstrap = bootstrapSnapshot {
            let missing = Set(bootstrap.items.filter { $0.state == .missing }.map(\.id))
            if missing.contains("homebrew") {
                return "Install Homebrew"
            }
            if missing.contains("yabai-binary") || missing.contains("skhd-binary") {
                return "Install Dependencies"
            }
        }

        guard let snapshot = doctorSnapshot else { return nil }
        let capabilityByKey = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0) })

        if let yabaiBinary = capabilityByKey["yabai-binary"], yabaiBinary.status == .blocked {
            return "Install yabai"
        }
        if let yabaiDaemon = capabilityByKey["yabai-daemon"], yabaiDaemon.status != .available {
            return "Start yabai"
        }
        if let yabaiQuery = capabilityByKey["yabai-query"], yabaiQuery.status != .available {
            return "yabai not responding"
        }
        if snapshot.missionControlChecks.contains(where: { $0.status == .warning }) {
            return "Mission Control settings"
        }
        if let sa = capabilityByKey["scripting-addition"], sa.status == .degraded || hasObservedScriptingAdditionRuntimeFailure {
            return "Fix Scripting Addition"
        }
        if let skhdBinary = capabilityByKey["skhd-binary"], skhdBinary.status == .blocked {
            return "Install skhd (optional)"
        }
        return nil
    }

    func updateRuntimeDiagnosticsMode(for snapshot: LiveStateSnapshot?) {
        let mode = runtimeActivityMode
        let polling = currentPollingIntervalSeconds()
        let keepOnTop = currentKeepOnTopEnforcementIntervalSeconds()
        let degradation = performanceDegradationMode
        mutateRuntimeDiagnostics {
            $0.runtimeActivityMode = mode.title
            $0.currentPollingIntervalSeconds = polling
            $0.currentKeepOnTopIntervalSeconds = keepOnTop
            $0.performanceMode = degradation.title
            $0.performanceModeDetail = degradation.detail ?? ""
        }
    }

    var hasVisibleTilePilotWindow: Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.title == "TilePilot"
        }
    }

    var hasActiveOverlayTargets: Bool {
        (showWindowBadgeOverlay || showWindowOutlineOverlay) && !windowBadges.isEmpty
    }

    var hasActiveKeepOnTopWindows: Bool {
        guard keepOnTopEnforcementEnabled else { return false }
        guard let snapshot = latestLiveStateSnapshot ?? liveStateSnapshot, snapshot.source == .yabai, !snapshot.degraded else { return false }
        let activeSpace = activeSpaceIndex(in: snapshot)
        return snapshot.windows.contains { window in
            guard !window.isHidden && !window.isMinimized && window.isVisible else { return false }
            guard window.floating else { return false }
            guard window.space == activeSpace else { return false }
            return appForegroundPolicy(for: window.app) == .keepFrontWhenFloating
        }
    }
}
