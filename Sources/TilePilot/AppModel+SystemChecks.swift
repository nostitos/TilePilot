import Foundation

@MainActor
extension AppModel {
    var coreChecklistItems: [DoctorChecklistItem] {
        checklistItems.filter(\.isCore)
    }

    var setupChecklistItems: [SetupCheckItem] {
        bootstrapSnapshot?.items ?? []
    }

    var setupCoreItems: [SetupCheckItem] {
        setupChecklistItems.filter { ["xcode-clt", "homebrew", "yabai-binary", "skhd-binary"].contains($0.id) }
    }

    var setupServiceItems: [SetupCheckItem] {
        setupChecklistItems.filter {
            [
                "brew-tap-koekeishiya",
                "brew-service-yabai",
                "brew-service-skhd",
                "start-at-logon",
                "accessibility-permission",
            ].contains($0.id)
        }
    }

    var setupSummaryLine: String {
        guard let snapshot = bootstrapSnapshot else { return "Setup scan has not run yet" }
        let missingCount = snapshot.items.filter { $0.state == .missing }.count
        let warningCount = snapshot.items.filter { $0.state == .warning }.count
        if missingCount == 0 && warningCount == 0 {
            return "Ready · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
        }
        return "\(missingCount) missing · \(warningCount) warnings · \(snapshot.generatedAt.formatted(date: .omitted, time: .standard))"
    }

    var systemCheckRows: [SystemCheckRow] {
        let setupByID = Dictionary(uniqueKeysWithValues: setupChecklistItems.map { ($0.id, $0) })
        let capabilityByKey = Dictionary(uniqueKeysWithValues: (doctorSnapshot?.capabilities ?? []).map { ($0.key, $0) })
        let missionControlChecks = doctorSnapshot?.missionControlChecks ?? []

        let xcode = setupByID["xcode-clt"]
        let homebrew = setupByID["homebrew"]
        let yabaiBinarySetup = setupByID["yabai-binary"]
        let skhdBinarySetup = setupByID["skhd-binary"]
        let yabaiServiceSetup = setupByID["brew-service-yabai"]
        let skhdServiceSetup = setupByID["brew-service-skhd"]
        let startAtLogonSetup = setupByID["start-at-logon"]
        let accessibilitySetup = setupByID["accessibility-permission"]

        let yabaiBinaryCap = capabilityByKey["yabai-binary"]
        let skhdBinaryCap = capabilityByKey["skhd-binary"]
        let yabaiDaemonCap = capabilityByKey["yabai-daemon"]
        let skhdDaemonCap = capabilityByKey["skhd-daemon"]
        let yabaiQueryCap = capabilityByKey["yabai-query"]
        let accessibilityCap = capabilityByKey["accessibility"]
        let scriptingAdditionCap = capabilityByKey["scripting-addition"]

        var rows: [SystemCheckRow] = []

        let xcodeStatus = mappedSystemStatus(from: xcode?.state) ?? .notice
        rows.append(SystemCheckRow(
            id: "xcode-clt",
            title: "Xcode Command Line Tools",
            detail: xcode?.detail ?? "Needed by Homebrew and terminal tooling on a fresh Mac.",
            status: xcodeStatus,
            actions: xcodeStatus == .good ? [.recheck] : [.installCLT, .recheck]
        ))

        let homebrewStatus = mappedSystemStatus(from: homebrew?.state) ?? .notice
        rows.append(SystemCheckRow(
            id: "homebrew",
            title: "Homebrew",
            detail: homebrew?.detail ?? "Package manager used to install yabai and skhd.",
            status: homebrewStatus,
            actions: homebrewStatus == .good ? [.recheck] : [.installDependencies, .recheck]
        ))

        let yabaiInstallStatus = mergedSystemStatus([
            mappedSystemStatus(from: yabaiBinarySetup?.state),
            mappedSystemStatus(from: yabaiBinaryCap?.status),
        ])
        rows.append(SystemCheckRow(
            id: "yabai-installed",
            title: "yabai Installed",
            detail: firstDetail(yabaiBinaryCap?.message, yabaiBinarySetup?.detail, fallback: "Install yabai to enable desktop/window runtime controls."),
            status: yabaiInstallStatus,
            actions: yabaiInstallStatus == .good ? [.recheck] : [.installDependencies, .recheck]
        ))

        let skhdInstallStatus = mergedSystemStatus([
            mappedSystemStatus(from: skhdBinarySetup?.state),
            mappedSystemStatus(from: skhdBinaryCap?.status),
        ])
        rows.append(SystemCheckRow(
            id: "skhd-installed",
            title: "skhd Installed",
            detail: firstDetail(skhdBinaryCap?.message, skhdBinarySetup?.detail, fallback: "Optional, but recommended for keyboard shortcut workflows."),
            status: skhdInstallStatus,
            actions: skhdInstallStatus == .good ? [.recheck] : [.installDependencies, .recheck]
        ))

        let yabaiRunningStatus = mergedSystemStatus([
            mappedSystemStatus(from: yabaiServiceSetup?.state),
            mappedSystemStatus(from: yabaiDaemonCap?.status),
            mappedSystemStatus(from: yabaiQueryCap?.status),
        ])
        rows.append(SystemCheckRow(
            id: "yabai-running",
            title: "yabai Running",
            detail: firstDetail(
                yabaiQueryCap?.message,
                yabaiDaemonCap?.message,
                yabaiServiceSetup?.detail,
                fallback: "Start yabai to control windows/desktops from TilePilot."
            ),
            status: yabaiRunningStatus,
            actions: yabaiRunningStatus == .good ? [.recheck] : [.startYabai, .restartYabai, .recheck]
        ))

        let skhdRunningStatus = mergedSystemStatus([
            mappedSystemStatus(from: skhdServiceSetup?.state),
            mappedSystemStatus(from: skhdDaemonCap?.status),
        ])
        rows.append(SystemCheckRow(
            id: "skhd-running",
            title: "skhd Running",
            detail: firstDetail(skhdDaemonCap?.message, skhdServiceSetup?.detail, fallback: "Start skhd for keyboard shortcuts."),
            status: skhdRunningStatus,
            actions: skhdRunningStatus == .good ? [.recheck] : [.startSkhd, .restartSkhd, .recheck]
        ))

        let startAtLogonStatus = mappedSystemStatus(from: startAtLogonSetup?.state) ?? .notice
        rows.append(SystemCheckRow(
            id: "start-at-logon",
            title: "Start TilePilot at Logon",
            detail: firstDetail(
                startAtLogonSetup?.detail,
                fallback: "Recommended so TilePilot appears in the menu bar after sign-in."
            ),
            status: startAtLogonStatus,
            actions: startAtLogonStatus == .good
                ? [.openLoginItemsSettings, .recheck]
                : [.enableStartAtLogon, .openLoginItemsSettings, .recheck]
        ))

        let rawAccessibilityStatus = mergedSystemStatus([
            mappedSystemStatus(from: accessibilitySetup?.state),
            mappedSystemStatus(from: accessibilityCap?.status),
        ])
        let accessibilityStatus: SystemCheckStatus
        switch rawAccessibilityStatus {
        case .error: accessibilityStatus = .warning
        default: accessibilityStatus = rawAccessibilityStatus
        }
        rows.append(SystemCheckRow(
            id: "accessibility",
            title: "Accessibility Permission (Optional)",
            detail: firstDetail(
                accessibilitySetup?.detail,
                accessibilityCap?.message,
                fallback: "Needed only for some TilePilot UI automations. Core app flows still work without it."
            ),
            status: accessibilityStatus,
            actions: accessibilityStatus == .good ? [.recheck] : [.requestAccessibilityAccess, .openAccessibilitySettings, .recheck]
        ))

        let missionWarningCount = missionControlChecks.filter { $0.status == .warning }.count
        let missionUnknownCount = missionControlChecks.filter { $0.status == .unknown }.count
        let missionStatus: SystemCheckStatus
        if missionWarningCount > 0 {
            missionStatus = .warning
        } else if missionUnknownCount > 0 || missionControlChecks.isEmpty {
            missionStatus = .notice
        } else {
            missionStatus = .good
        }
        let missionDetail: String
        if missionWarningCount > 0 {
            missionDetail = "\(missionWarningCount) Mission Control setting(s) need review for predictable desktop behavior."
        } else if missionUnknownCount > 0 {
            missionDetail = "Some Mission Control settings could not be verified."
        } else if missionControlChecks.isEmpty {
            missionDetail = "Run Recheck to verify Mission Control settings."
        } else {
            missionDetail = "Mission Control settings look compatible."
        }
        rows.append(SystemCheckRow(
            id: "mission-control",
            title: "Mission Control Settings",
            detail: missionDetail,
            status: missionStatus,
            actions: missionStatus == .good
                ? [.openMissionControlSettings, .recheck]
                : [.openMissionControlSettings, .openMissionControlKeyboardShortcuts, .recheck]
        ))

        let saStatus = mappedSystemStatus(from: scriptingAdditionCap?.status) ?? .notice
        let normalizedSAStatus: SystemCheckStatus = saStatus == .error ? .warning : saStatus
        rows.append(SystemCheckRow(
            id: "scripting-addition",
            title: "Desktop Move Shortcuts (Advanced)",
            detail: scriptingAdditionDetail(from: scriptingAdditionCap),
            status: normalizedSAStatus,
            actions: normalizedSAStatus == .good
                ? [.openMissionControlKeyboardShortcuts, .recheck]
                : [.fixScriptingAddition, .openMissionControlKeyboardShortcuts, .recheck]
        ))

        return rows.sorted { lhs, rhs in
            let lhsIsAdvanced = lhs.id == "scripting-addition"
            let rhsIsAdvanced = rhs.id == "scripting-addition"
            if lhsIsAdvanced != rhsIsAdvanced {
                return !lhsIsAdvanced
            }
            if lhs.status.severityRank != rhs.status.severityRank {
                return lhs.status.severityRank > rhs.status.severityRank
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var systemSummaryLine: String {
        let errors = systemCheckRows.filter { $0.status == .error }.count
        let warnings = systemCheckRows.filter { $0.status == .warning }.count
        let notices = systemCheckRows.filter { $0.status == .notice }.count
        if errors == 0 && warnings == 0 && notices == 0 {
            return "Ready"
        }
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) need action") }
        if warnings > 0 { parts.append("\(warnings) recommended") }
        if notices > 0 { parts.append("\(notices) informational") }
        return parts.joined(separator: " · ")
    }

    var systemPrimaryActions: [SystemCheckAction] {
        var actions: [SystemCheckAction] = []
        for row in systemCheckRows where row.status != .good {
            for action in row.actions where action != .recheck && !actions.contains(action) {
                actions.append(action)
                if actions.count >= 5 { return actions }
            }
        }
        return actions
    }

    func performSystemCheckAction(_ action: SystemCheckAction) {
        switch action {
        case .installDependencies:
            runSetupInstallerInTerminal()
        case .installCLT:
            requestXcodeCLTInstallPrompt()
        case .startYabai:
            startBrewServiceYabai()
        case .startSkhd:
            startBrewServiceSkhd()
        case .enableStartAtLogon:
            enableStartAtLogon()
        case .openLoginItemsSettings:
            openLoginItemsSettings()
        case .openAccessibilitySettings:
            openAccessibilitySettings()
        case .requestAccessibilityAccess:
            requestAccessibilityAccessPrompt()
        case .fixScriptingAddition:
            runScriptingAdditionRepairInTerminal()
        case .openMissionControlSettings:
            openMissionControlSettings()
        case .openMissionControlKeyboardShortcuts:
            openMissionControlKeyboardShortcuts()
        case .restartYabai:
            restartYabaiBestEffort()
        case .restartSkhd:
            restartSkhdBestEffort()
        case .recheck:
            Task { [weak self] in
                guard let self else { return }
                await self.refreshBootstrapSetup()
                await self.refreshDoctor()
            }
        }
    }

    var advancedChecklistItems: [DoctorChecklistItem] {
        checklistItems.filter { !$0.isCore }
    }

    private var checklistItems: [DoctorChecklistItem] {
        var items: [DoctorChecklistItem] = []
        for item in doctorSnapshot?.capabilities ?? [] {
            switch item.key {
            case "yabai-binary":
                items.append(checklist(from: item, title: "yabai installed", isCore: true))
            case "skhd-binary":
                items.append(checklist(from: item, title: "skhd installed", isCore: true))
            case "yabai-daemon":
                items.append(checklist(from: item, title: "yabai daemon running", isCore: true))
            case "skhd-daemon":
                items.append(checklist(from: item, title: "skhd daemon running", isCore: true))
            case "accessibility":
                items.append(checklist(from: item, title: "Accessibility permission", isCore: true))
            case "yabai-query":
                items.append(checklist(from: item, title: "Live yabai query", isCore: true))
            case "scripting-addition":
                items.append(scriptingAdditionChecklist(from: item))
            default:
                continue
            }
        }
        return items.sorted { lhs, rhs in
            if lhs.isCore != rhs.isCore { return lhs.isCore && !rhs.isCore }
            if lhs.status.severityRank != rhs.status.severityRank {
                return lhs.status.severityRank > rhs.status.severityRank
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func checklist(from capability: CapabilityState, title: String, isCore: Bool) -> DoctorChecklistItem {
        DoctorChecklistItem(
            title: title,
            isCore: isCore,
            status: capability.status,
            detail: capability.message,
            remediation: capability.remediationSteps
        )
    }

    private func scriptingAdditionChecklist(from capability: CapabilityState) -> DoctorChecklistItem {
        if hasObservedScriptingAdditionRuntimeFailure {
            var remediation = capability.remediationSteps
            if !remediation.contains(where: { $0.localizedCaseInsensitiveContains("repair") || $0.localizedCaseInsensitiveContains("install") }) {
                remediation.append("Use System -> Fix Scripting Addition to reinstall the scripting addition.")
            }
            return DoctorChecklistItem(
                title: "Desktop move support",
                isCore: false,
                status: .degraded,
                detail: "Runtime commands reported scripting-addition failures recently. Desktop move shortcuts are unavailable until it is repaired.",
                remediation: remediation
            )
        }

        var detail = capability.message
        if detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            detail = "Optional advanced feature. Regular desktop switching can use macOS Mission Control shortcuts without scripting addition."
        }
        if capability.status == .available {
            detail = "Advanced desktop/window move shortcuts are available."
        }
        var remediation = capability.remediationSteps
        if capability.status != .available, !remediation.contains(where: { $0.localizedCaseInsensitiveContains("mission control") }) {
            remediation.append("You can still switch desktops using macOS Mission Control keyboard shortcuts.")
        }
        return DoctorChecklistItem(
            title: "Desktop move support",
            isCore: false,
            status: capability.status,
            detail: detail,
            remediation: remediation
        )
    }

    private func mappedSystemStatus(from setupState: SetupCheckState?) -> SystemCheckStatus? {
        guard let setupState else { return nil }
        switch setupState {
        case .installed:
            return .good
        case .warning:
            return .warning
        case .missing:
            return .error
        case .unknown:
            return .notice
        }
    }

    private func mappedSystemStatus(from capabilityStatus: CapabilityStatus?) -> SystemCheckStatus? {
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

    private func mergedSystemStatus(_ statuses: [SystemCheckStatus?]) -> SystemCheckStatus {
        statuses.compactMap { $0 }.max(by: { $0.severityRank < $1.severityRank }) ?? .notice
    }

    private func firstDetail(_ candidates: String?..., fallback: String) -> String {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { continue }
            return trimmed
        }
        return fallback
    }

    private func scriptingAdditionDetail(from capability: CapabilityState?) -> String {
        guard let capability else {
            return "Not yet checked. Optional for advanced desktop/window move shortcuts."
        }
        if capability.status == .available {
            return "Advanced desktop/window move shortcuts are available."
        }
        return "Optional advanced feature. Regular desktop switching can use macOS Mission Control shortcuts without scripting addition."
    }
}
