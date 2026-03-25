import Foundation

@MainActor
extension AppModel {
    private var setupGuideItemsByID: [String: SetupCheckItem] {
        Dictionary(uniqueKeysWithValues: setupChecklistItems.map { ($0.id, $0) })
    }

    private var screenRecordingAuthorizedForSetupGuide: Bool {
        megamapCaptureService.screenRecordingAuthorized()
    }

    var setupGuideSteps: [SetupGuideStep] {
        let capabilityByKey = Dictionary(uniqueKeysWithValues: (doctorSnapshot?.capabilities ?? []).map { ($0.key, $0) })
        let missionControlChecks = doctorSnapshot?.missionControlChecks ?? []

        let yabaiBinarySetup = setupGuideItemsByID["yabai-binary"]
        let skhdBinarySetup = setupGuideItemsByID["skhd-binary"]
        let yabaiServiceSetup = setupGuideItemsByID["helper-service-yabai"]
        let skhdServiceSetup = setupGuideItemsByID["helper-service-skhd"]
        let startAtLogonSetup = setupGuideItemsByID["start-at-logon"]
        let accessibilitySetup = setupGuideItemsByID["accessibility-permission"]
        let bundledHelpersSetup = setupGuideItemsByID["bundled-helpers"]

        let helperInstallStatus = mergedGuideStatus([
            mappedGuideStatus(from: yabaiBinarySetup?.state),
            mappedGuideStatus(from: skhdBinarySetup?.state),
            mappedGuideStatus(from: capabilityByKey["yabai-binary"]?.status),
            mappedGuideStatus(from: capabilityByKey["skhd-binary"]?.status),
        ])

        let helperServicesStatus = mergedGuideStatus([
            mappedGuideStatus(from: yabaiServiceSetup?.state),
            mappedGuideStatus(from: skhdServiceSetup?.state),
            mappedGuideStatus(from: capabilityByKey["yabai-daemon"]?.status),
            mappedGuideStatus(from: capabilityByKey["skhd-daemon"]?.status),
            mappedGuideStatus(from: capabilityByKey["yabai-query"]?.status),
        ])

        let accessibilityStatus = mergedGuideStatus([
            mappedGuideStatus(from: accessibilitySetup?.state),
            mappedGuideStatus(from: capabilityByKey["accessibility"]?.status),
        ], defaultStatus: .notice)

        let startAtLogonStatus = mappedGuideStatus(from: startAtLogonSetup?.state) ?? .notice

        let missionControlStatus: SystemCheckStatus
        if missionControlChecks.contains(where: { $0.status == .warning }) {
            missionControlStatus = .warning
        } else if missionControlChecks.isEmpty || missionControlChecks.contains(where: { $0.status == .unknown }) {
            missionControlStatus = .notice
        } else {
            missionControlStatus = .good
        }

        let screenRecordingStatus: SystemCheckStatus = screenRecordingAuthorizedForSetupGuide ? .good : .notice

        return [
            SetupGuideStep(
                kind: .installHelpers,
                category: .essential,
                title: "Install TilePilot Helpers",
                summary: helperInstallStatus == .good ? "TilePilot helpers are installed." : "TilePilot cannot manage windows or shortcuts until its helpers are installed.",
                whyItMatters: "TilePilot uses yabai for desktop and window control, and skhd for global hotkeys.",
                whatToDo: setupGuideItemsByID["bundled-helpers"]?.state == .installed
                    ? "Install the bundled helpers into your user account."
                    : "Use the packaged TilePilot app from /Applications. This build does not include bundled helpers.",
                detail: firstNonEmptyGuideDetail([
                    bundledHelpersSetup?.detail,
                    yabaiBinarySetup?.detail,
                    skhdBinarySetup?.detail,
                    capabilityByKey["yabai-binary"]?.message,
                    capabilityByKey["skhd-binary"]?.message,
                ]),
                verificationText: "TilePilot will recheck helper installation automatically.",
                status: helperInstallStatus,
                isBlocking: true,
                isSkippable: true,
                primaryAction: bundledHelpersSetup?.state == .installed ? .installDependencies : nil,
                secondaryActions: [.recheck]
            ),
            SetupGuideStep(
                kind: .startHelperServices,
                category: .essential,
                title: "Start Helper Services",
                summary: helperServicesStatus == .good ? "Helper services are running." : "TilePilot helpers are installed, but the background services are not fully running yet.",
                whyItMatters: "TilePilot can only query desktops and react to shortcuts when yabai and skhd are active.",
                whatToDo: "Start the helper services. If you just migrated to a new Mac, also open Accessibility settings and re-enable TilePilot, yabai, and skhd if they are listed there.",
                detail: firstNonEmptyGuideDetail([
                    capabilityByKey["yabai-query"]?.message,
                    capabilityByKey["yabai-daemon"]?.message,
                    capabilityByKey["skhd-daemon"]?.message,
                    helperServicesStatus == .good ? nil : "A migrated or newly installed Mac can leave yabai or skhd unable to stay running until macOS permissions are re-approved.",
                    yabaiServiceSetup?.detail,
                    skhdServiceSetup?.detail,
                ]),
                verificationText: "TilePilot will recheck helper services automatically.",
                status: helperServicesStatus,
                isBlocking: true,
                isSkippable: true,
                primaryAction: .startYabai,
                secondaryActions: [.openAccessibilitySettings, .restartYabai, .restartSkhd, .recheck]
            ),
            SetupGuideStep(
                kind: .accessibility,
                category: .recommended,
                title: "Review Accessibility Permissions",
                summary: accessibilityStatus == .good ? "Accessibility access is already granted for TilePilot." : "Accessibility improves focus, raise, helper startup recovery, and some UI automation flows.",
                whyItMatters: "TilePilot uses Accessibility for some window focus and bring-to-front fallbacks. On a new or migrated Mac, macOS may also require yabai and skhd to be re-enabled in Accessibility before they work reliably again.",
                whatToDo: "Request TilePilot's permission first. Then open Accessibility settings and make sure TilePilot is enabled. If you migrated to a new Mac, also look for yabai and skhd there and re-enable them if they appear.",
                detail: firstNonEmptyGuideDetail([
                    accessibilityStatus == .good ? nil : "If yabai still reports socket or startup failures after migration, the missing permission is often in the Accessibility list rather than inside TilePilot itself.",
                    accessibilitySetup?.detail,
                    capabilityByKey["accessibility"]?.message,
                ]),
                verificationText: "Return to TilePilot after changing the setting. It will recheck automatically.",
                status: accessibilityStatus == .good ? .good : .notice,
                isBlocking: false,
                isSkippable: true,
                primaryAction: accessibilityStatus == .good ? nil : .requestAccessibilityAccess,
                secondaryActions: accessibilityStatus == .good ? [] : [.openAccessibilitySettings, .recheck]
            ),
            SetupGuideStep(
                kind: .startAtLogon,
                category: .recommended,
                title: "Start TilePilot at Login",
                summary: startAtLogonStatus == .good ? "TilePilot is configured to launch at login." : "TilePilot is easier to rely on when it starts automatically after sign-in.",
                whyItMatters: "TilePilot is a menu bar app. Starting it automatically avoids a dead-looking desktop after login.",
                whatToDo: "Enable TilePilot at login, or open Login Items if you want to review it manually.",
                detail: firstNonEmptyGuideDetail([
                    startAtLogonSetup?.detail,
                ]),
                verificationText: "TilePilot will recheck the launch agent automatically.",
                status: startAtLogonStatus,
                isBlocking: false,
                isSkippable: true,
                primaryAction: startAtLogonStatus == .good ? nil : .enableStartAtLogon,
                secondaryActions: [.openLoginItemsSettings, .recheck]
            ),
            SetupGuideStep(
                kind: .missionControl,
                category: .recommended,
                title: "Review Mission Control Settings",
                summary: missionControlStatus == .good ? "Mission Control settings look compatible." : "Mission Control settings can affect how reliably macOS desktops behave for TilePilot.",
                whyItMatters: "Desktop ordering and display grouping need to be predictable for overview and desktop navigation features.",
                whatToDo: "Open Mission Control settings and confirm TilePilot’s recommended macOS desktop behavior.",
                detail: missionControlGuideDetail(missionControlChecks),
                verificationText: "Recheck after reviewing the settings.",
                status: missionControlStatus,
                isBlocking: false,
                isSkippable: true,
                primaryAction: missionControlStatus == .good ? nil : .openMissionControlSettings,
                secondaryActions: missionControlStatus == .good ? [] : [.openMissionControlKeyboardShortcuts, .recheck]
            ),
            SetupGuideStep(
                kind: .screenRecording,
                category: .featureOptional,
                title: "Enable Screen Recording for MegaMap",
                summary: screenRecordingStatus == .good ? "Screen Recording is enabled for MegaMap screenshots." : "MegaMap needs Screen Recording only for real screenshots. Without it, TilePilot shows the synthetic fallback.",
                whyItMatters: "MegaMap uses macOS screen capture APIs to build real desktop screenshots.",
                whatToDo: "Use Enable Screen Recording first. TilePilot will request capture access, then open Screen Recording settings.",
                detail: screenRecordingStatus == .good
                    ? "TilePilot can already capture real MegaMap screenshots."
                    : "If TilePilot is not listed in Screen Recording yet, macOS has not registered the capture request. Use Enable Screen Recording again, then reopen the settings page and look for TilePilot manually.",
                verificationText: "After you return to TilePilot, Screen Recording will be rechecked automatically.",
                status: screenRecordingStatus,
                isBlocking: false,
                isSkippable: true,
                primaryAction: screenRecordingStatus == .good ? nil : .requestScreenRecordingAccess,
                secondaryActions: screenRecordingStatus == .good ? [] : [.openScreenRecordingSettings, .recheck]
            ),
        ]
    }

    var incompleteSetupGuideSteps: [SetupGuideStep] {
        setupGuideSteps.filter { !$0.isSatisfied }
    }

    var incompleteEssentialSetupGuideSteps: [SetupGuideStep] {
        setupGuideSteps.filter { $0.category == .essential && !$0.isSatisfied }
    }

    var hasIncompleteEssentialSetupGuideSteps: Bool {
        !incompleteEssentialSetupGuideSteps.isEmpty
    }

    var currentSetupGuideStep: SetupGuideStep? {
        let steps = setupGuideSteps
        guard !steps.isEmpty else { return nil }
        if let selectedKind = setupGuidePresentationState.selectedStepKind,
           let selected = steps.first(where: { $0.kind == selectedKind }) {
            return selected
        }
        return incompleteSetupGuideSteps.first ?? steps.first
    }

    var setupGuideCompletionTitle: String {
        hasIncompleteEssentialSetupGuideSteps ? "TilePilot still needs setup" : "TilePilot is ready"
    }

    var setupGuideCompletionDetail: String {
        if let current = currentSetupGuideStep, !current.isSatisfied {
            return current.summary
        }
        if incompleteSetupGuideSteps.isEmpty {
            return "All required steps are complete. Optional permissions can still be reviewed later from System or Guided Setup."
        }
        return "The essential setup is complete. Optional and recommended steps can still improve how TilePilot works."
    }

    func presentSetupGuide(source: SetupGuidePresentationSource = .manual, startingAt stepKind: SetupGuideStepKind? = nil) {
        acknowledgeInitialStatusIfNeeded()
        let selected = stepKind ?? preferredStartingSetupGuideStep(for: source)?.kind
        setupGuidePresentationState = SetupGuidePresentationState(isPresented: true, source: source, selectedStepKind: selected)
    }

    func dismissSetupGuide() {
        if setupGuidePresentationState.source == .automatic, hasIncompleteEssentialSetupGuideSteps {
            hasDismissedAutomaticSetupGuideThisSession = true
        }
        setupGuidePresentationState = .hidden
    }

    func continueSetupGuide() {
        if let next = nextIncompleteSetupGuideStep(after: setupGuidePresentationState.selectedStepKind) {
            setupGuidePresentationState.selectedStepKind = next.kind
        } else {
            dismissSetupGuide()
        }
    }

    func selectSetupGuideStep(_ kind: SetupGuideStepKind) {
        setupGuidePresentationState.selectedStepKind = kind
    }

    func maybePresentSetupGuideAutomatically() {
        guard shouldAutoPresentSetupGuide else { return }
        presentSetupGuide(source: .automatic)
    }

    func refreshSetupGuidePresentationAfterStateChange() {
        if setupGuidePresentationState.isPresented {
            if let selectedKind = setupGuidePresentationState.selectedStepKind,
               let selected = setupGuideSteps.first(where: { $0.kind == selectedKind }),
               !selected.isSatisfied {
                return
            }
            setupGuidePresentationState.selectedStepKind = nextIncompleteSetupGuideStep(after: setupGuidePresentationState.selectedStepKind)?.kind
            return
        }

        maybePresentSetupGuideAutomatically()
    }

    private var shouldAutoPresentSetupGuide: Bool {
        guard bootstrapSnapshot != nil, doctorSnapshot != nil else { return false }
        guard hasIncompleteEssentialSetupGuideSteps else { return false }
        guard !hasDismissedAutomaticSetupGuideThisSession else { return false }
        return true
    }

    private func preferredStartingSetupGuideStep(for source: SetupGuidePresentationSource) -> SetupGuideStep? {
        switch source {
        case .automatic:
            return incompleteEssentialSetupGuideSteps.first ?? incompleteSetupGuideSteps.first
        case .manual:
            return incompleteSetupGuideSteps.first ?? setupGuideSteps.first
        }
    }

    private func nextIncompleteSetupGuideStep(after kind: SetupGuideStepKind?) -> SetupGuideStep? {
        let steps = setupGuideSteps
        let unresolved = steps.filter { !$0.isSatisfied }
        guard !unresolved.isEmpty else { return nil }
        guard let kind,
              let selectedIndex = steps.firstIndex(where: { $0.kind == kind }) else {
            return unresolved.first
        }

        if selectedIndex + 1 < steps.count,
           let next = steps[(selectedIndex + 1)...].first(where: { !$0.isSatisfied }) {
            return next
        }

        return unresolved.first
    }

    private func mappedGuideStatus(from setupState: SetupCheckState?) -> SystemCheckStatus? {
        guard let setupState else { return nil }
        switch setupState {
        case .installed:
            return .good
        case .missing:
            return .error
        case .warning:
            return .warning
        case .unknown:
            return .notice
        }
    }

    private func mappedGuideStatus(from capabilityStatus: CapabilityStatus?) -> SystemCheckStatus? {
        guard let capabilityStatus else { return nil }
        switch capabilityStatus {
        case .available:
            return .good
        case .unknown:
            return .notice
        case .degraded:
            return .warning
        case .unsupported, .blocked:
            return .error
        }
    }

    private func mergedGuideStatus(_ statuses: [SystemCheckStatus?], defaultStatus: SystemCheckStatus = .error) -> SystemCheckStatus {
        statuses.compactMap { $0 }.max(by: { $0.severityRank < $1.severityRank }) ?? defaultStatus
    }

    private func firstNonEmptyGuideDetail(_ candidates: [String?]) -> String? {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { continue }
            return trimmed
        }
        return nil
    }

    private func missionControlGuideDetail(_ checks: [MissionControlCheck]) -> String {
        if checks.isEmpty {
            return "TilePilot has not verified Mission Control settings yet."
        }
        let warnings = checks.filter { $0.status == .warning }
        if !warnings.isEmpty {
            return warnings.map(\.message).joined(separator: " ")
        }
        let unknowns = checks.filter { $0.status == .unknown }
        if !unknowns.isEmpty {
            return unknowns.map(\.message).joined(separator: " ")
        }
        return "Mission Control settings already look compatible."
    }
}
