import Foundation

@MainActor
extension AppModel {
    private var setupItemsByID: [String: SetupCheckItem] {
        Dictionary(uniqueKeysWithValues: setupChecklistItems.map { ($0.id, $0) })
    }

    private var capabilitiesByKey: [String: CapabilityState] {
        Dictionary(uniqueKeysWithValues: (doctorSnapshot?.capabilities ?? []).map { ($0.key, $0) })
    }

    private var helpersInstalledForSetup: Bool {
        setupItemInstalled("yabai-binary") && setupItemInstalled("skhd-binary")
    }

    private var helperServicesRunningForSetup: Bool {
        setupItemInstalled("brew-service-yabai") && setupItemInstalled("brew-service-skhd")
    }

    private var appleDeveloperToolsNeedAttentionForSetup: Bool {
        if setupItemMissing("xcode-clt") {
            return true
        }
        guard !helpersInstalledForSetup else { return false }
        guard let status = externalInstallerStatus else { return false }
        switch status.blocker {
        case .appleDeveloperToolsMissing:
            return setupItemMissing("xcode-clt")
        case .appleDeveloperToolsOutdated:
            return true
        default:
            return false
        }
    }

    var primarySetupAction: SetupNextAction {
        if doctorSnapshot == nil || bootstrapSnapshot == nil {
            return .recheck
        }
        if appleDeveloperToolsNeedAttentionForSetup {
            return .updateAppleDeveloperTools
        }
        if !helpersInstalledForSetup {
            return .installHelpers
        }
        if !helperServicesRunningForSetup {
            return .startHelperServices
        }
        return .ready
    }

    var primarySetupActionLabel: String {
        primarySetupAction.buttonTitle
    }

    var primarySetupActionDetail: String {
        if let status = externalInstallerStatus {
            switch primarySetupAction {
            case .updateAppleDeveloperTools:
                if status.blocker == .appleDeveloperToolsMissing || status.blocker == .appleDeveloperToolsOutdated {
                    return status.summary
                }
            case .installHelpers:
                if status.recommendedAction == .installHelpers {
                    return status.summary
                }
            case .startHelperServices:
                if status.blocker == .serviceStartFailed || status.recommendedAction == .startHelperServices {
                    return status.summary
                }
            case .recheck, .ready:
                break
            }
        }

        switch primarySetupAction {
        case .updateAppleDeveloperTools:
            return "TilePilot needs Apple Developer Tools before it can install its helper tools."
        case .installHelpers:
            return "TilePilot needs two helper tools to manage windows and keyboard shortcuts. TilePilot can install them for you."
        case .startHelperServices:
            return "TilePilot helpers are installed, but the background services still need to be started."
        case .recheck:
            return "TilePilot is still checking this Mac. Recheck setup if the status looks stale."
        case .ready:
            return "TilePilot helpers look ready."
        }
    }

    var primarySetupSummaryLine: String {
        switch primarySetupAction {
        case .ready:
            if let snapshot = bootstrapSnapshot {
                return "Ready · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
            }
            return "Ready"
        case .recheck:
            return "Setup scan needed"
        default:
            return "\(primarySetupAction.summaryTitle) · \(primarySetupActionDetail)"
        }
    }

    var setupRequiredRows: [SystemCheckRow] {
        let requiredIDs: Set<String> = [
            "xcode-clt",
            "yabai-installed",
            "skhd-installed",
            "yabai-running",
            "skhd-running",
        ]
        return systemCheckRows.filter { requiredIDs.contains($0.id) }
    }

    var setupOptionalRows: [SystemCheckRow] {
        let optionalIDs: Set<String> = [
            "start-at-logon",
            "accessibility",
            "mission-control",
        ]
        return systemCheckRows.filter { optionalIDs.contains($0.id) }
    }

    var setupBlockingRows: [SystemCheckRow] {
        let blockingStatuses: Set<SystemCheckStatus> = [.warning, .error, .notice]
        return setupRequiredRows.filter { blockingStatuses.contains($0.status) }
    }

    var setupOptionalRowsNeedingAttention: [SystemCheckRow] {
        let attentionStatuses: Set<SystemCheckStatus> = [.warning, .notice, .error]
        return setupOptionalRows.filter { attentionStatuses.contains($0.status) }
    }

    var isPrimarySetupActionInFlight: Bool {
        switch primarySetupAction {
        case .installHelpers:
            return isLaunchingSetupInstaller
        case .recheck:
            return isRefreshing || isRefreshingBootstrap
        default:
            return false
        }
    }

    func performPrimarySetupAction() {
        performSetupAction(primarySetupAction)
    }

    func performSetupAction(_ action: SetupNextAction) {
        switch action {
        case .updateAppleDeveloperTools:
            requestXcodeCLTInstallPrompt()
        case .installHelpers:
            runSetupInstallerInTerminal()
        case .startHelperServices:
            startHelperServicesBestEffort()
        case .recheck:
            Task { [weak self] in
                guard let self else { return }
                await self.refreshBootstrapSetup()
                await self.refreshDoctor()
            }
        case .ready:
            lastActionMessage = "TilePilot already looks ready."
            lastErrorMessage = nil
        }
    }

    private func setupItemInstalled(_ id: String) -> Bool {
        setupItemsByID[id]?.state == .installed
    }

    private func setupItemMissing(_ id: String) -> Bool {
        setupItemsByID[id]?.state == .missing
    }

    var setupDisplayRows: [SystemCheckRow] {
        setupRequiredRows + setupOptionalRows
    }

    var setupStateNeedsAttention: Bool {
        primarySetupAction != .ready
    }
}
