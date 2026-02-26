import AppKit
import ApplicationServices
import Foundation
import SwiftUI

struct DoctorChecklistItem: Identifiable {
    let id = UUID()
    let title: String
    let isCore: Bool
    let status: CapabilityStatus
    let detail: String
    let remediation: [String]
}

enum CoachActionID: String, CaseIterable, Identifiable {
    case balanceSpace
    case layoutBSPAndBalance
    case layoutStack
    case toggleFloat
    case focusWest
    case focusEast
    case focusNorth
    case focusSouth
    case browserReliefPlaceholder

    var id: String { rawValue }
}

struct CoachActionCard: Identifiable {
    let id: CoachActionID
    let title: String
    let subtitle: String
    let category: String
    let requiredCapabilities: [String]
    let enabled: Bool
    let disabledReason: String?
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var doctorSnapshot: DoctorSnapshot?
    @Published private(set) var bootstrapSnapshot: SetupBootstrapSnapshot?
    @Published private(set) var liveStateSnapshot: LiveStateSnapshot?
    @Published private(set) var requestedCoachTab: CoachTab?
    @Published private(set) var shortcutEntries: [ShortcutEntry] = []
    @Published var managedConfigDraft: String = ""
    @Published private(set) var commandLogs: [CommandLogEntry] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingBootstrap = false
    @Published private(set) var isRefreshingLiveState = false
    @Published private(set) var isRefreshingShortcuts = false
    @Published private(set) var isRefreshingConfig = false
    @Published private(set) var isSavingConfig = false
    @Published private(set) var isRestoringConfig = false
    @Published private(set) var activeActionID: CoachActionID?
    @Published private(set) var isLaunchingSetupInstaller = false
    @Published private(set) var hasAcknowledgedInitialStatus = false
    @Published var lastErrorMessage: String?
    @Published var lastActionMessage: String?
    @Published var lastExportURL: URL?
    @Published var lastSetupInstallerURL: URL?
    @Published private(set) var shortcutFilePath: String?
    @Published private(set) var shortcutParseIssues: [String] = []
    @Published private(set) var configFilePath: String?
    @Published private(set) var configBackups: [ConfigBackupInfo] = []
    @Published private(set) var configFileExists = false
    @Published private(set) var configHasManagedSection = false
    @Published private(set) var configDiffPreviewText: String = "No changes."
    @Published private(set) var yabaiConfigFilePath: String?
    @Published private(set) var yabaiConfigBackups: [ConfigBackupInfo] = []
    @Published private(set) var yabaiConfigFileExists = false
    @Published private(set) var yabaiConfigHasManagedSection = false
    @Published private(set) var yabaiConfigDiffPreviewText: String = "No changes."
    @Published private(set) var isRefreshingYabaiConfig = false
    @Published private(set) var isSavingYabaiConfig = false
    @Published private(set) var isRestoringYabaiConfig = false
    @Published var windowBehaviorPolicyDraft = ManagedWindowBehaviorPolicy.default

    private let doctorService = DoctorService()
    private let bootstrapService = BootstrapService()
    private let yabaiStateService = YabaiStateService()
    private let skhdShortcutService = SkhdShortcutService()
    private let configService = ConfigService()
    private let yabaiRulesConfigService = YabaiRulesConfigService()
    private var autoRefreshTask: Task<Void, Never>?
    private var statePollingTask: Task<Void, Never>?
    private var degradedModeActive = false
    private var consecutiveMismatchSamples = 0
    private var consecutiveHealthySamples = 0
    private let degradedEnterThreshold = 3
    private let degradedExitThreshold = 5
    private var originalManagedConfigSection: String = ""
    private var loadedFullConfigContent: String = ""
    private var originalWindowBehaviorPolicy = ManagedWindowBehaviorPolicy.default
    private var originalYabaiManagedConfigSection: String = ""
    private var externalYabaiAppBehaviorByName: [String: AppTilingBehavior] = [:]
    private let initialSetupLandingShownDefaultsKey = "TilePilot.initialSetupLandingShown"

    func startIfNeeded() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshDoctor()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await self.refreshDoctor()
            }
        }

        guard statePollingTask == nil else { return }
        statePollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLiveState()
            while !Task.isCancelled {
                let interval = self.currentPollingIntervalSeconds()
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self.refreshLiveState()
            }
        }

        if shortcutEntries.isEmpty {
            Task { [weak self] in
                await self?.refreshShortcuts()
            }
        }

        if bootstrapSnapshot == nil {
            Task { [weak self] in
                await self?.refreshBootstrapSetup()
            }
        }

        if configFilePath == nil {
            Task { [weak self] in
                await self?.refreshConfig()
            }
        }

        if yabaiConfigFilePath == nil {
            Task { [weak self] in
                await self?.refreshWindowBehaviorConfig()
            }
        }
    }

    func stop() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        statePollingTask?.cancel()
        statePollingTask = nil
    }

    func refreshDoctor() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await doctorService.runDoctor()
        doctorSnapshot = result.snapshot
        prependCommandLogs(result.commandLogs)
        lastErrorMessage = nil
        lastActionMessage = nil
    }

    func refreshBootstrapSetup() async {
        guard !isRefreshingBootstrap else { return }
        isRefreshingBootstrap = true
        defer { isRefreshingBootstrap = false }

        let result = await bootstrapService.runBootstrapChecks()
        bootstrapSnapshot = result.snapshot
        prependCommandLogs(result.commandLogs)
    }

    func acknowledgeInitialStatusIfNeeded() {
        if !hasAcknowledgedInitialStatus {
            hasAcknowledgedInitialStatus = true
        }
    }

    func requestOpenCoachTab(_ tab: CoachTab) {
        requestedCoachTab = tab
    }

    func consumeRequestedCoachTab() -> CoachTab? {
        defer { requestedCoachTab = nil }
        return requestedCoachTab
    }

    func consumeShouldStartOnSetupTab() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: initialSetupLandingShownDefaultsKey) {
            return false
        }
        defaults.set(true, forKey: initialSetupLandingShownDefaultsKey)
        return true
    }

    func refreshLiveState() async {
        guard !isRefreshingLiveState else { return }
        isRefreshingLiveState = true
        defer { isRefreshingLiveState = false }

        let poll = await yabaiStateService.pollLiveState()
        applyDegradedModeCounters(yabaiWindowTotal: poll.yabaiWindowTotal, fallbackWindowTotal: poll.fallbackWindowTotal)

        let snapshot = makeLiveStateSnapshot(from: poll)
        liveStateSnapshot = snapshot
    }

    func refreshShortcuts() async {
        guard !isRefreshingShortcuts else { return }
        isRefreshingShortcuts = true
        defer { isRefreshingShortcuts = false }

        let result = await skhdShortcutService.loadShortcuts()
        shortcutEntries = result.entries.sorted {
            if $0.category != $1.category { return $0.category < $1.category }
            if $0.combo != $1.combo { return $0.combo < $1.combo }
            return $0.sourceLine < $1.sourceLine
        }
        shortcutFilePath = result.filePath
        shortcutParseIssues = result.issues
    }

    func refreshConfig() async {
        guard !isRefreshingConfig else { return }
        isRefreshingConfig = true
        defer { isRefreshingConfig = false }

        do {
            let state = try await configService.loadConfigDocument()
            applyConfigDocumentState(state, preserveUserDraftIfDirty: false)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Failed to load config: \(error.localizedDescription)"
            lastActionMessage = nil
        }
    }

    func refreshWindowBehaviorConfig() async {
        guard !isRefreshingYabaiConfig else { return }
        isRefreshingYabaiConfig = true
        defer { isRefreshingYabaiConfig = false }
        do {
            let state = try await yabaiRulesConfigService.loadConfigDocument()
            applyYabaiConfigDocumentState(state)
        } catch {
            lastErrorMessage = "Failed to load yabairc settings: \(error.localizedDescription)"
            lastActionMessage = nil
        }
    }

    func resetManagedConfigDraft() {
        managedConfigDraft = originalManagedConfigSection
        recomputeConfigDiffPreview()
        lastActionMessage = "Reverted draft to the last loaded managed section."
        lastErrorMessage = nil
    }

    func saveManagedConfigSection() {
        guard !isSavingConfig else { return }
        isSavingConfig = true
        let draft = managedConfigDraft

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isSavingConfig = false } }
            do {
                let result = try await self.configService.saveManagedSection(body: draft)
                let reloaded = try await self.configService.loadConfigDocument()
                await MainActor.run {
                    self.applyConfigDocumentState(reloaded, preserveUserDraftIfDirty: false)
                    let mode = result.wasInsert ? "Inserted" : "Updated"
                    self.lastActionMessage = "\(mode) TilePilot managed section in skhdrc."
                    self.lastErrorMessage = nil
                }

                await self.refreshShortcuts()
                await self.runBestEffortSkhdRestart(afterConfigChange: true)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Config save failed: \(error.localizedDescription)"
                    self.lastActionMessage = nil
                }
            }
        }
    }

    func restoreLatestConfigBackup() {
        guard let backup = configBackups.first else {
            lastErrorMessage = "No backups available."
            lastActionMessage = nil
            return
        }
        restoreConfigBackup(backup)
    }

    func restoreConfigBackup(_ backup: ConfigBackupInfo) {
        guard !isRestoringConfig else { return }
        isRestoringConfig = true

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isRestoringConfig = false } }
            do {
                _ = try await self.configService.restoreBackup(path: backup.path)
                let reloaded = try await self.configService.loadConfigDocument()
                await MainActor.run {
                    self.applyConfigDocumentState(reloaded, preserveUserDraftIfDirty: false)
                    self.lastActionMessage = "Restored backup: \(URL(fileURLWithPath: backup.path).lastPathComponent)"
                    self.lastErrorMessage = nil
                }

                await self.refreshShortcuts()
                await self.runBestEffortSkhdRestart(afterConfigChange: true)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Restore failed: \(error.localizedDescription)"
                    self.lastActionMessage = nil
                }
            }
        }
    }

    func resetWindowBehaviorDraft() {
        windowBehaviorPolicyDraft = originalWindowBehaviorPolicy
        recomputeYabaiConfigDiffPreview()
        lastActionMessage = "Reverted Window Behavior draft."
        lastErrorMessage = nil
    }

    func saveWindowBehaviorPolicy() {
        guard !isSavingYabaiConfig else { return }
        isSavingYabaiConfig = true
        let draft = windowBehaviorPolicyDraft
        let previousPolicy = originalWindowBehaviorPolicy

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isSavingYabaiConfig = false } }
            do {
                _ = try await self.yabaiRulesConfigService.saveWindowBehaviorPolicy(draft)
                let reloaded = try await self.yabaiRulesConfigService.loadConfigDocument()
                await MainActor.run {
                    self.applyYabaiConfigDocumentState(reloaded, preserveDraftIfDirty: false)
                    self.lastActionMessage = "Window behavior saved to yabairc."
                    self.lastErrorMessage = nil
                }
                await self.applyWindowBehaviorRuntime(previous: previousPolicy, current: draft)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Saving yabairc settings failed: \(error.localizedDescription)"
                    self.lastActionMessage = nil
                }
            }
        }
    }

    func restoreYabaiConfigBackup(_ backup: ConfigBackupInfo) {
        guard !isRestoringYabaiConfig else { return }
        isRestoringYabaiConfig = true
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isRestoringYabaiConfig = false } }
            do {
                _ = try await self.yabaiRulesConfigService.restoreBackup(path: backup.path)
                let reloaded = try await self.yabaiRulesConfigService.loadConfigDocument()
                await MainActor.run {
                    self.applyYabaiConfigDocumentState(reloaded, preserveDraftIfDirty: false)
                    self.lastActionMessage = "Restored yabairc backup: \(URL(fileURLWithPath: backup.path).lastPathComponent)"
                    self.lastErrorMessage = nil
                }
                await self.applyWindowBehaviorRuntime(previous: self.originalWindowBehaviorPolicy, current: reloaded.policy)
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Restore yabairc backup failed: \(error.localizedDescription)"
                    self.lastActionMessage = nil
                }
            }
        }
    }

    func enableManualTilingMode() {
        windowBehaviorPolicyDraft.manualTilingModeEnabled = true
        recomputeYabaiConfigDiffPreview()
        saveWindowBehaviorPolicy()
    }

    func disableManualTilingMode() {
        windowBehaviorPolicyDraft.manualTilingModeEnabled = false
        recomputeYabaiConfigDiffPreview()
        saveWindowBehaviorPolicy()
    }

    func setHoverFocusMode(_ mode: HoverFocusMode) {
        windowBehaviorPolicyDraft.hoverFocusMode = mode
        recomputeYabaiConfigDiffPreview()
        saveWindowBehaviorPolicy()
    }

    func updateManualTilingModeDraft(_ enabled: Bool) {
        windowBehaviorPolicyDraft.manualTilingModeEnabled = enabled
        recomputeYabaiConfigDiffPreview()
    }

    func updateHoverFocusModeDraft(_ mode: HoverFocusMode) {
        windowBehaviorPolicyDraft.hoverFocusMode = mode
        recomputeYabaiConfigDiffPreview()
    }

    func disableHoverFocus() {
        windowBehaviorPolicyDraft.hoverFocusMode = .off
        recomputeYabaiConfigDiffPreview()
        saveWindowBehaviorPolicy()
    }

    func tileFocusedWindowNow() {
        setFocusedWindowFloating(false)
    }

    func floatFocusedWindowNow() {
        setFocusedWindowFloating(true)
    }

    func toggleFocusedWindowTiling() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--toggle", "float"], timeout: 1.5),
            successMessage: "Toggled focused window tiling."
        )
    }

    func openWindowBehaviorSettings() {
        requestOpenCoachTab(.windowBehavior)
    }

    var canRunYabaiRuntimeCommands: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return map["yabai-binary"] == .available && map["yabai-daemon"] == .available
    }

    var yabaiRuntimeControlDisabledReason: String? {
        guard let snapshot = doctorSnapshot else { return "Check Setup first." }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0) })
        if map["yabai-binary"]?.status != .available {
            return map["yabai-binary"]?.message ?? "yabai is not installed."
        }
        if map["yabai-daemon"]?.status != .available {
            return map["yabai-daemon"]?.message ?? "yabai is not running."
        }
        return nil
    }

    func copyShortcutCombo(_ entry: ShortcutEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.combo, forType: .string)
        lastActionMessage = "Copied shortcut combo."
        lastErrorMessage = nil
    }

    func copyShortcutCommand(_ entry: ShortcutEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.command, forType: .string)
        lastActionMessage = "Copied shortcut command."
        lastErrorMessage = nil
    }

    func updateManagedConfigDraft(_ newValue: String) {
        managedConfigDraft = newValue
        recomputeConfigDiffPreview()
    }

    func performCoachAction(_ actionID: CoachActionID) {
        guard activeActionID == nil else { return }
        let availability = actionAvailability(for: actionID)
        guard availability.enabled else {
            lastErrorMessage = availability.disabledReason ?? "Action is unavailable."
            lastActionMessage = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            await self.runCoachAction(actionID)
        }
    }

    func exportDiagnostics() {
        guard let snapshot = doctorSnapshot else {
            lastErrorMessage = "Run Setup Check before exporting diagnostics."
            return
        }

        let report = DiagnosticsReport(
            generatedAt: Date(),
            systemProfile: snapshot.systemProfile,
            health: snapshot,
            capabilities: snapshot.capabilities,
            recentCommands: Array(commandLogs.prefix(50))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(report)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("tilepilot-diagnostics-\(stamp).json")
            try data.write(to: url, options: .atomic)
            lastExportURL = url
            lastErrorMessage = nil
            lastActionMessage = "Diagnostics exported to \(url.lastPathComponent)"
        } catch {
            lastErrorMessage = "Diagnostics export failed: \(error.localizedDescription)"
        }
    }

    func copyIssueReadySummary() {
        guard let snapshot = doctorSnapshot else {
            lastErrorMessage = "Run Setup Check before copying a status summary."
            return
        }

        let failing = snapshot.capabilities
            .filter { $0.status != .available }
            .sorted { $0.status.severityRank > $1.status.severityRank }

        var lines: [String] = []
        lines.append("TilePilot Status Summary")
        lines.append("Generated: \(snapshot.generatedAt.formatted(date: .abbreviated, time: .standard))")
        lines.append("macOS: \(snapshot.systemProfile.macOSVersion)")
        lines.append("Build: \(snapshot.systemProfile.macOSBuild ?? "unknown")")
        lines.append("Arch: \(snapshot.systemProfile.arch)")
        lines.append("yabai: \(snapshot.systemProfile.yabaiVersion ?? "not detected")")
        lines.append("skhd: \(snapshot.systemProfile.skhdVersion ?? "not detected")")
        lines.append("Health: \(snapshot.healthBadge.title)")
        lines.append("")
        lines.append("Capabilities:")
        for item in failing.prefix(8) {
            lines.append("- \(item.key): \(item.status.rawValue) (\(item.reasonCode ?? "no-reason"))")
            lines.append("  \(item.message)")
        }
        if !snapshot.compatibilityWarnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            snapshot.compatibilityWarnings.forEach { lines.append("- \($0)") }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        lastErrorMessage = nil
        lastActionMessage = "Issue-ready summary copied to clipboard."
    }

    func runSetupInstallerInTerminal() {
        guard !isLaunchingSetupInstaller else { return }
        isLaunchingSetupInstaller = true

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isLaunchingSetupInstaller = false } }

            do {
                let scriptURL = try self.bootstrapService.prepareInstallerScript()
                let openResult = await self.doctorService.runSupportCommand(
                    ShellCommand("/usr/bin/open", ["-a", "Terminal", scriptURL.path], timeout: 3.0)
                )

                await MainActor.run {
                    self.lastSetupInstallerURL = scriptURL
                    self.appendCommandLog(from: openResult)
                    if openResult.isSuccess {
                        self.lastActionMessage = "Opened setup installer in Terminal."
                        self.lastErrorMessage = nil
                    } else {
                        self.lastErrorMessage = "Failed to open installer in Terminal. Try opening \(scriptURL.path) manually."
                        self.lastActionMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Failed to prepare setup installer: \(error.localizedDescription)"
                    self.lastActionMessage = nil
                }
            }
        }
    }

    func openSystemSettings() {
        openURLCandidates([
            "x-apple.systempreferences:",
        ])
    }

    func openAccessibilitySettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:",
        ])
    }

    func requestXcodeCLTInstallPrompt() {
        acknowledgeInitialStatusIfNeeded()
        runSupportCommand(
            ShellCommand("/usr/bin/xcode-select", ["--install"], timeout: 2.0),
            successMessage: "Requested Xcode Command Line Tools installer prompt."
        )
    }

    func requestAccessibilityAccessPrompt() {
        acknowledgeInitialStatusIfNeeded()
        let alreadyTrusted = AXIsProcessTrusted()
        if alreadyTrusted {
            lastActionMessage = "Accessibility access is already granted."
            lastErrorMessage = nil
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        lastActionMessage = "Requested Accessibility access prompt. If no prompt appears, open Accessibility Settings manually."
        lastErrorMessage = nil

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            await self?.refreshBootstrapSetup()
            await self?.refreshDoctor()
        }
    }

    func openMissionControlSettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.preference.expose",
            "x-apple.systempreferences:",
        ])
    }

    func restartYabaiBestEffort() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "--restart-service"], timeout: 2.0),
            successMessage: "Requested yabai service restart."
        )
    }

    func restartSkhdBestEffort() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["skhd", "--restart-service"], timeout: 2.0),
            successMessage: "Requested skhd service restart."
        )
    }

    func startBrewServiceYabai() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "--start-service"], timeout: 5.0),
            successMessage: "Requested `yabai --start-service`."
        )
    }

    func startBrewServiceSkhd() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["skhd", "--start-service"], timeout: 5.0),
            successMessage: "Requested `skhd --start-service`."
        )
    }

    private func runSupportCommand(_ command: ShellCommand, successMessage: String) {
        guard !isRefreshing else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.doctorService.runSupportCommand(command)
            await MainActor.run {
                let logEntry = CommandLogEntry(
                    id: UUID(),
                    command: result.command,
                    startedAt: result.startedAt,
                    endedAt: result.endedAt,
                    durationMs: result.durationMs,
                    exitStatus: result.exitStatus,
                    stdoutSnippet: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description,
                    stderrSnippet: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description,
                    errorType: result.errorType
                )
                self.commandLogs = Array(([logEntry] + self.commandLogs).prefix(200))
                if result.isSuccess {
                    self.lastActionMessage = successMessage
                    self.lastErrorMessage = nil
                    Task {
                        await self.refreshLiveState()
                        await self.refreshDoctor()
                        await self.refreshBootstrapSetup()
                        await self.refreshWindowBehaviorConfig()
                    }
                } else {
                    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if result.command.contains("yabai"), stderr.contains("could not connect") {
                        self.lastErrorMessage = "yabai is not running. Start yabai, then try again."
                    } else if result.command.contains("yabai"), (stderr.contains("no such file") || stderr.contains("not found")) {
                        self.lastErrorMessage = "yabai is not installed or not available in PATH."
                    } else {
                        self.lastErrorMessage = "Command failed: \(result.command)"
                    }
                    self.lastActionMessage = nil
                }
            }
        }
    }

    private func openURLCandidates(_ candidates: [String]) {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                lastActionMessage = "Opened System Settings."
                lastErrorMessage = nil
                return
            }
        }
        lastErrorMessage = "Unable to open System Settings."
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
        setupChecklistItems.filter { ["brew-tap-koekeishiya", "brew-service-yabai", "brew-service-skhd", "accessibility-permission"].contains($0.id) }
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

    var windowBehaviorSummaryLine: String {
        let mode = windowBehaviorPolicyDraft.manualTilingModeEnabled ? "Manual tiling ON" : "Manual tiling OFF"
        let hover = "Hover focus: \(windowBehaviorPolicyDraft.hoverFocusMode.displayName)"
        return "\(mode) · \(hover)"
    }

    var isWindowBehaviorDraftDirty: Bool {
        windowBehaviorPolicyDraft != originalWindowBehaviorPolicy
    }

    var availableAppNamesFromLiveState: [String] {
        let names = Set((liveStateSnapshot?.windows ?? []).map(\.app).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return names.sorted()
    }

    var appNamesForBehaviorEditor: [String] {
        let names = Set(availableAppNamesFromLiveState)
            .union(windowBehaviorPolicyDraft.neverTileApps)
            .union(windowBehaviorPolicyDraft.alwaysTileApps)
        return names.sorted()
    }

    var focusedWindowState: WindowState? {
        liveStateSnapshot?.windows.first(where: \.focused)
    }

    var canControlFocusedWindow: Bool {
        focusedWindowState != nil && doctorSnapshot != nil
    }

    var shouldShowWindowBehaviorRecommendation: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let capabilityByKey = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return capabilityByKey["yabai-binary"] == .available && !yabaiConfigHasManagedSection
    }

    var advancedChecklistItems: [DoctorChecklistItem] {
        checklistItems.filter { !$0.isCore }
    }

    var actionCards: [CoachActionCard] {
        CoachActionID.allCases.map { actionID in
            let meta = actionMeta(for: actionID)
            let availability = actionAvailability(for: actionID)
            return CoachActionCard(
                id: actionID,
                title: meta.title,
                subtitle: meta.subtitle,
                category: meta.category,
                requiredCapabilities: meta.requiredCapabilities,
                enabled: availability.enabled,
                disabledReason: availability.disabledReason,
            )
        }
    }

    var quickActionCards: [CoachActionCard] {
        actionCards.filter { ["Layouts", "Window"].contains($0.category) && $0.id != .browserReliefPlaceholder }
    }

    func addNeverTileApp(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !windowBehaviorPolicyDraft.neverTileApps.contains(trimmed) {
            windowBehaviorPolicyDraft.neverTileApps.append(trimmed)
            windowBehaviorPolicyDraft.neverTileApps.sort()
        }
        windowBehaviorPolicyDraft.alwaysTileApps.removeAll { $0 == trimmed }
        recomputeYabaiConfigDiffPreview()
    }

    func removeNeverTileApp(_ name: String) {
        windowBehaviorPolicyDraft.neverTileApps.removeAll { $0 == name }
        recomputeYabaiConfigDiffPreview()
    }

    func addAlwaysTileApp(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !windowBehaviorPolicyDraft.alwaysTileApps.contains(trimmed) {
            windowBehaviorPolicyDraft.alwaysTileApps.append(trimmed)
            windowBehaviorPolicyDraft.alwaysTileApps.sort()
        }
        windowBehaviorPolicyDraft.neverTileApps.removeAll { $0 == trimmed }
        recomputeYabaiConfigDiffPreview()
    }

    func removeAlwaysTileApp(_ name: String) {
        windowBehaviorPolicyDraft.alwaysTileApps.removeAll { $0 == name }
        recomputeYabaiConfigDiffPreview()
    }

    func appTilingBehavior(for appName: String) -> AppTilingBehavior {
        let key = normalizedAppRuleKey(appName)
        if windowBehaviorPolicyDraft.neverTileApps.contains(where: { normalizedAppRuleKey($0) == key }) {
            return .neverTile
        }
        if windowBehaviorPolicyDraft.alwaysTileApps.contains(where: { normalizedAppRuleKey($0) == key }) {
            return .alwaysTile
        }
        return externalYabaiAppBehaviorByName[key] ?? .useDefault
    }

    func appBehaviorSourceNote(for appName: String) -> String? {
        let key = normalizedAppRuleKey(appName)
        if windowBehaviorPolicyDraft.neverTileApps.contains(where: { normalizedAppRuleKey($0) == key }) ||
            windowBehaviorPolicyDraft.alwaysTileApps.contains(where: { normalizedAppRuleKey($0) == key }) {
            return nil
        }
        guard let behavior = externalYabaiAppBehaviorByName[key] else { return nil }
        switch behavior {
        case .neverTile:
            return "Applied by an existing rule in your yabairc (outside TilePilot)."
        case .alwaysTile:
            return "Auto-tiling is forced by an existing rule in your yabairc (outside TilePilot)."
        case .useDefault:
            return nil
        }
    }

    func setAppTilingBehavior(_ behavior: AppTilingBehavior, for appName: String) {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        windowBehaviorPolicyDraft.neverTileApps.removeAll { $0 == trimmed }
        windowBehaviorPolicyDraft.alwaysTileApps.removeAll { $0 == trimmed }

        switch behavior {
        case .useDefault:
            break
        case .neverTile:
            windowBehaviorPolicyDraft.neverTileApps.append(trimmed)
            windowBehaviorPolicyDraft.neverTileApps = Array(Set(windowBehaviorPolicyDraft.neverTileApps)).sorted()
        case .alwaysTile:
            windowBehaviorPolicyDraft.alwaysTileApps.append(trimmed)
            windowBehaviorPolicyDraft.alwaysTileApps = Array(Set(windowBehaviorPolicyDraft.alwaysTileApps)).sorted()
        }
        recomputeYabaiConfigDiffPreview()
    }

    var isManagedConfigDraftDirty: Bool {
        managedConfigDraft != originalManagedConfigSection
    }

    private var checklistItems: [DoctorChecklistItem] {
        guard let snapshot = doctorSnapshot else { return [] }
        let capabilityByKey = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0) })
        var items: [DoctorChecklistItem] = []

        if let item = capabilityByKey["accessibility"] {
            items.append(checklist(from: item, title: "TilePilot Accessibility (optional)", isCore: false))
        }
        if let item = capabilityByKey["yabai-binary"] {
            items.append(checklist(from: item, title: "yabai installed", isCore: true))
        }
        if let item = capabilityByKey["yabai-daemon"] {
            items.append(checklist(from: item, title: "yabai daemon running", isCore: true))
        }
        if let item = capabilityByKey["yabai-query"] {
            items.append(checklist(from: item, title: "yabai query socket reachable", isCore: true))
        }
        if let item = capabilityByKey["skhd-binary"] {
            items.append(checklist(from: item, title: "skhd installed", isCore: false))
        }
        if let item = capabilityByKey["skhd-daemon"] {
            items.append(checklist(from: item, title: "skhd daemon running", isCore: false))
        }
        if let item = capabilityByKey["scripting-addition"] {
            items.append(checklist(from: item, title: "scripting addition", isCore: false))
        }

        for check in snapshot.missionControlChecks {
            let status: CapabilityStatus
            switch check.status {
            case .pass: status = .available
            case .warning: status = .degraded
            case .unknown: status = .unknown
            }
            items.append(
                DoctorChecklistItem(
                    title: "Mission Control: \(check.key)",
                    isCore: true,
                    status: status,
                    detail: check.message,
                    remediation: ["Expected \(check.expected), actual \(check.actual ?? "unknown")."]
                )
            )
        }

        return items
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

    private func currentPollingIntervalSeconds() -> Double {
        let anyVisibleNonSettingsWindow = NSApp.windows.contains { window in
            window.isVisible && window.title == "TilePilot"
        }
        return anyVisibleNonSettingsWindow ? 0.9 : 2.5
    }

    private var shouldSoftenInitialBlockedStatus: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        return snapshot.healthBadge == .blocked && !hasAcknowledgedInitialStatus
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

    private var shouldDowngradeBlockedToSetupNeededInMenuBar: Bool {
        guard let snapshot = doctorSnapshot, snapshot.healthBadge == .blocked else { return false }

        let blockedKeys = Set(snapshot.capabilities.filter { $0.status == .blocked }.map(\.key))
        if blockedKeys.isEmpty {
            return false
        }

        let commonSetupBlockedKeys: Set<String> = ["accessibility", "yabai-binary", "skhd-binary", "yabai-query"]
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

        return blockedKeys == Set(["accessibility"]) || blockedKeys == Set(["accessibility", "yabai-query"])
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
            ["accessibility", "yabai-binary", "skhd-binary", "yabai-daemon", "skhd-daemon", "yabai-query"].contains(capability.key)
        }
        return allSetupish && liveStateSnapshot == nil
    }

    private func primaryMenuBarSummary() -> String? {
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
        if let sa = capabilityByKey["scripting-addition"], sa.status == .degraded || sa.status == .unknown {
            return "Optional SA features unavailable"
        }
        if let skhdBinary = capabilityByKey["skhd-binary"], skhdBinary.status == .blocked {
            return "Install skhd (optional)"
        }
        return nil
    }

    private func applyConfigDocumentState(_ state: ConfigDocumentState, preserveUserDraftIfDirty: Bool) {
        let wasDirty = isManagedConfigDraftDirty
        configFilePath = state.filePath
        configFileExists = state.fileExists
        configHasManagedSection = state.hasManagedSection
        configBackups = state.backups
        loadedFullConfigContent = state.fullContent
        originalManagedConfigSection = state.managedSectionBody

        if !(preserveUserDraftIfDirty && wasDirty) {
            managedConfigDraft = state.managedSectionBody
        }
        recomputeConfigDiffPreview()
    }

    private func applyYabaiConfigDocumentState(_ state: YabaiConfigDocumentState, preserveDraftIfDirty: Bool = true) {
        yabaiConfigFilePath = state.filePath
        yabaiConfigFileExists = state.fileExists
        yabaiConfigHasManagedSection = state.hasManagedSection
        yabaiConfigBackups = state.backups
        externalYabaiAppBehaviorByName = parseExternalYabaiAppBehaviors(from: state.fullContent)
        let wasDirty = isWindowBehaviorDraftDirty
        originalWindowBehaviorPolicy = state.policy
        originalYabaiManagedConfigSection = state.managedSectionBody
        if !(preserveDraftIfDirty && wasDirty) {
            windowBehaviorPolicyDraft = state.policy
        }
        recomputeYabaiConfigDiffPreview()
    }

    private func recomputeConfigDiffPreview() {
        configDiffPreviewText = configService.buildManagedSectionDiff(
            original: originalManagedConfigSection,
            proposed: managedConfigDraft
        )
    }

    private func recomputeYabaiConfigDiffPreview() {
        let proposed = yabaiRulesConfigService.renderManagedBody(for: windowBehaviorPolicyDraft)
        yabaiConfigDiffPreviewText = yabaiRulesConfigService.buildManagedSectionDiff(
            original: originalYabaiManagedConfigSection,
            proposed: proposed
        )
    }

    private func normalizedAppRuleKey(_ appName: String) -> String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func parseExternalYabaiAppBehaviors(from fullContent: String) -> [String: AppTilingBehavior] {
        var map: [String: AppTilingBehavior] = [:]
        let begin = yabaiRulesConfigService.beginMarker
        let end = yabaiRulesConfigService.endMarker
        var inManagedBlock = false

        for rawLine in fullContent.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line == begin {
                inManagedBlock = true
                continue
            }
            if line == end {
                inManagedBlock = false
                continue
            }
            if inManagedBlock || line.isEmpty || line.hasPrefix("#") { continue }
            guard line.contains("rule --add") else { continue }

            let behavior: AppTilingBehavior?
            if line.contains("manage=off") {
                behavior = .neverTile
            } else if line.contains("manage=on") {
                behavior = .alwaysTile
            } else {
                behavior = nil
            }
            guard let behavior else { continue }
            guard let appPattern = parseAppPattern(fromRuleLine: line) else { continue }

            for app in expandExternalAppPattern(appPattern) {
                let key = normalizedAppRuleKey(app)
                guard !key.isEmpty else { continue }
                map[key] = behavior
            }
        }
        return map
    }

    private func parseAppPattern(fromRuleLine line: String) -> String? {
        guard let range = line.range(of: #"app=""#) else { return nil }
        let start = range.upperBound
        guard let end = line[start...].firstIndex(of: "\"") else { return nil }
        return String(line[start..<end])
    }

    private func expandExternalAppPattern(_ pattern: String) -> [String] {
        let unescaped = pattern.replacingOccurrences(of: #"\"#, with: "")
        if unescaped == ".*" { return [] }

        if let exact = unwrapAnchoredExactPattern(unescaped) {
            return [exact]
        }

        if let group = unwrapAnchoredAlternationPattern(unescaped) {
            return group
        }

        if !looksRegexLike(unescaped) {
            return [unescaped]
        }
        return []
    }

    private func unwrapAnchoredExactPattern(_ pattern: String) -> String? {
        guard pattern.hasPrefix("^"), pattern.hasSuffix("$") else { return nil }
        let core = String(pattern.dropFirst().dropLast())
        guard !core.isEmpty, !looksRegexLike(core) else { return nil }
        return core
    }

    private func unwrapAnchoredAlternationPattern(_ pattern: String) -> [String]? {
        guard pattern.hasPrefix("^("), pattern.hasSuffix(")$") else { return nil }
        let core = String(pattern.dropFirst(2).dropLast(2))
        let parts = core.split(separator: "|").map(String.init)
        guard !parts.isEmpty else { return nil }
        var apps: [String] = []
        for part in parts {
            let name = part.replacingOccurrences(of: #"\"#, with: "")
            guard !name.isEmpty, !looksRegexLike(name) else { return nil }
            apps.append(name)
        }
        return apps
    }

    private func looksRegexLike(_ value: String) -> Bool {
        let regexMeta = CharacterSet(charactersIn: "[](){}.*+?|^$")
        return value.rangeOfCharacter(from: regexMeta) != nil
    }

    private func applyWindowBehaviorRuntime(previous: ManagedWindowBehaviorPolicy, current: ManagedWindowBehaviorPolicy) async {
        let focusResult = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "config", "focus_follows_mouse", current.hoverFocusMode.rawValue], timeout: 1.5)
        )
        await MainActor.run {
            self.appendCommandLog(from: focusResult)
            if !focusResult.isSuccess {
                self.lastActionMessage = "Saved settings, but runtime apply may require restarting yabai."
            }
        }

        let ruleCommands = yabaiRulesConfigService.runtimeRuleCommands(previous: previous, current: current)
        var ruleApplyFailed = false
        for command in ruleCommands {
            let result = await doctorService.runSupportCommand(command)
            await MainActor.run {
                self.appendCommandLog(from: result)
            }
            if !result.isSuccess {
                ruleApplyFailed = true
            }
        }

        let allNeverTiled = Set(current.neverTileApps)
        if !allNeverTiled.isEmpty {
            await floatOpenWindowsForApps(allNeverTiled)
        }

        await MainActor.run {
            if current.manualTilingModeEnabled {
                if !ruleApplyFailed {
                    self.lastActionMessage = "Manual Tiling Mode enabled. Existing windows stay as-is; new windows should stop auto-tiling."
                    self.lastErrorMessage = nil
                } else if self.lastErrorMessage == nil {
                    self.lastErrorMessage = "Saved settings, but some live yabai rules did not apply. Restart yabai if behavior looks wrong."
                }
            } else {
                self.lastActionMessage = "Manual Tiling Mode disabled. New windows will follow your normal yabai layout rules."
                self.lastErrorMessage = nil
            }
        }
        await refreshLiveState()
        await refreshDoctor()
        await refreshWindowBehaviorConfig()
    }

    private func floatOpenWindowsForApps(_ appNames: Set<String>) async {
        let names = Set(appNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !names.isEmpty else { return }
        let openWindows = liveStateSnapshot?.windows ?? []
        for window in openWindows where names.contains(window.app) && !window.floating {
            let result = await doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "window", String(window.id), "--toggle", "float"], timeout: 1.5)
            )
            await MainActor.run {
                self.appendCommandLog(from: result)
            }
            if result.isSuccess {
                await bringWindowToFront(windowID: window.id)
            }
        }
    }

    private func bringWindowToFront(windowID: Int) async {
        let raise = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "window", String(windowID), "--raise"], timeout: 1.5)
        )
        await MainActor.run {
            self.appendCommandLog(from: raise)
        }

        let focus = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--focus", String(windowID)], timeout: 1.5)
        )
        await MainActor.run {
            self.appendCommandLog(from: focus)
        }
    }

    private func setFocusedWindowFloating(_ shouldFloat: Bool) {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        if focused.floating == shouldFloat {
            lastActionMessage = shouldFloat ? "Focused window is already floating." : "Focused window is already tiled."
            lastErrorMessage = nil
            return
        }
        if shouldFloat {
            Task { [weak self] in
                guard let self else { return }
                let toggle = await self.doctorService.runSupportCommand(
                    ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--toggle", "float"], timeout: 1.5)
                )
                await MainActor.run {
                    self.appendCommandLog(from: toggle)
                    if !toggle.isSuccess {
                        self.lastErrorMessage = "Failed to float focused window."
                        self.lastActionMessage = nil
                    }
                }
                guard toggle.isSuccess else { return }
                await self.bringWindowToFront(windowID: focused.id)
                await MainActor.run {
                    self.lastActionMessage = "Focused window set to floating."
                    self.lastErrorMessage = nil
                }
                await self.refreshLiveState()
            }
        } else {
            runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--toggle", "float"], timeout: 1.5),
                successMessage: "Focused window set to tiled."
            )
        }
    }

    private func runBestEffortSkhdRestart(afterConfigChange: Bool) async {
        let result = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["skhd", "--restart-service"], timeout: 2.0)
        )
        await MainActor.run {
            self.appendCommandLog(from: result)
            if result.isSuccess {
                if afterConfigChange {
                    self.lastActionMessage = "Config saved and skhd restart requested."
                }
                self.lastErrorMessage = nil
            } else if afterConfigChange {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastActionMessage = "Config saved. skhd restart is best effort and may require manual restart."
                if !stderr.isEmpty {
                    self.lastErrorMessage = "skhd restart command failed: \(trimForUI(stderr))"
                }
            }
        }
        await refreshDoctor()
    }

    private func runCoachAction(_ actionID: CoachActionID) async {
        activeActionID = actionID
        defer { activeActionID = nil }

        let beforeSignature = liveStateSignature()
        let commands = actionCommands(for: actionID)
        guard !commands.isEmpty else {
            lastErrorMessage = "No commands defined for action."
            lastActionMessage = nil
            return
        }

        for command in commands {
            let result = await doctorService.runSupportCommand(command)
            appendCommandLog(from: result)
            if !result.isSuccess {
                lastErrorMessage = actionMeta(for: actionID).title + " failed"
                if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastErrorMessage = "\(actionMeta(for: actionID).title) failed: \(trimForUI(result.stderr))"
                }
                lastActionMessage = nil
                return
            }
        }

        await refreshLiveState()

        let afterSignature = liveStateSignature()
        if beforeSignature != nil, beforeSignature == afterSignature {
            lastActionMessage = "\(actionMeta(for: actionID).title) completed, but no visible state change was detected."
        } else {
            lastActionMessage = "\(actionMeta(for: actionID).title) completed."
        }
        lastErrorMessage = nil
    }

    private func appendCommandLog(from result: CommandResult) {
        let logEntry = CommandLogEntry(
            id: UUID(),
            command: result.command,
            startedAt: result.startedAt,
            endedAt: result.endedAt,
            durationMs: result.durationMs,
            exitStatus: result.exitStatus,
            stdoutSnippet: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description,
            stderrSnippet: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description,
            errorType: result.errorType
        )
        commandLogs = Array(([logEntry] + commandLogs).prefix(200))
    }

    private func prependCommandLogs(_ logs: [CommandLogEntry]) {
        guard !logs.isEmpty else { return }
        commandLogs = Array((logs + commandLogs).prefix(200))
    }

    private func liveStateSignature() -> String? {
        guard let snapshot = liveStateSnapshot else { return nil }
        let focusedWindow = snapshot.windows.first(where: \.focused)?.id ?? -1
        let focusedSpace = snapshot.spaces.first(where: \.focused)?.index ?? -1
        let layouts = snapshot.spaces.map { "\($0.index):\($0.layout ?? "?")" }.joined(separator: ",")
        return [
            snapshot.source.rawValue,
            snapshot.degraded ? "1" : "0",
            String(snapshot.yabaiWindowTotal ?? -1),
            String(snapshot.fallbackWindowTotal ?? -1),
            String(focusedWindow),
            String(focusedSpace),
            layouts,
        ].joined(separator: "|")
    }

    private func actionCommands(for actionID: CoachActionID) -> [ShellCommand] {
        switch actionID {
        case .balanceSpace:
            return [.init("/usr/bin/env", ["yabai", "-m", "space", "--balance"], timeout: 1.5)]
        case .layoutBSPAndBalance:
            return [
                .init("/usr/bin/env", ["yabai", "-m", "space", "--layout", "bsp"], timeout: 1.5),
                .init("/usr/bin/env", ["yabai", "-m", "space", "--balance"], timeout: 1.5),
            ]
        case .layoutStack:
            return [.init("/usr/bin/env", ["yabai", "-m", "space", "--layout", "stack"], timeout: 1.5)]
        case .toggleFloat:
            return [.init("/usr/bin/env", ["yabai", "-m", "window", "--toggle", "float"], timeout: 1.5)]
        case .focusWest:
            return [.init("/usr/bin/env", ["yabai", "-m", "window", "--focus", "west"], timeout: 1.5)]
        case .focusEast:
            return [.init("/usr/bin/env", ["yabai", "-m", "window", "--focus", "east"], timeout: 1.5)]
        case .focusNorth:
            return [.init("/usr/bin/env", ["yabai", "-m", "window", "--focus", "north"], timeout: 1.5)]
        case .focusSouth:
            return [.init("/usr/bin/env", ["yabai", "-m", "window", "--focus", "south"], timeout: 1.5)]
        case .browserReliefPlaceholder:
            return []
        }
    }

    private func actionAvailability(for actionID: CoachActionID) -> (enabled: Bool, disabledReason: String?) {
        let meta = actionMeta(for: actionID)

        if actionID == .browserReliefPlaceholder {
            return (false, "Browser Relief helper workflow is not implemented yet.")
        }

        guard let doctor = doctorSnapshot else {
            return (false, "Run Setup Check first to determine capabilities.")
        }

        let capabilityByKey = Dictionary(uniqueKeysWithValues: doctor.capabilities.map { ($0.key, $0) })
        for key in meta.requiredCapabilities {
            guard let capability = capabilityByKey[key] else {
                return (false, "Capability `\(key)` has not been evaluated yet.")
            }
            if capability.status == .blocked || capability.status == .unsupported {
                return (false, capability.message)
            }
            if key == "yabai-query", capability.status != .available {
                return (false, capability.message)
            }
            if key == "yabai-daemon", capability.status != .available {
                return (false, capability.message)
            }
            if key == "yabai-binary", capability.status != .available {
                return (false, capability.message)
            }
        }

        if meta.requiresLiveState {
            guard let snapshot = liveStateSnapshot else {
                return (false, "Waiting for live state.")
            }
            if snapshot.source == .stale {
                return (false, "Live state is stale.")
            }
        }

        if meta.disableInDegradedMode {
            if let snapshot = liveStateSnapshot, snapshot.degraded {
                return (false, "Disabled in degraded mode to avoid misleading workspace actions.")
            }
        }

        if activeActionID != nil {
            return (false, "Another action is currently running.")
        }

        return (true, nil)
    }

    private func actionMeta(for actionID: CoachActionID) -> (
        title: String,
        subtitle: String,
        category: String,
        requiredCapabilities: [String],
        requiresLiveState: Bool,
        disableInDegradedMode: Bool
    ) {
        switch actionID {
        case .balanceSpace:
            return ("Balance Space", "Balance current space tree", "Layouts", ["yabai-binary", "yabai-daemon", "yabai-query"], true, true)
        case .layoutBSPAndBalance:
            return ("BSP + Balance", "Set layout to BSP and balance", "Layouts", ["yabai-binary", "yabai-daemon", "yabai-query"], true, true)
        case .layoutStack:
            return ("Stack Layout", "Set current space layout to stack", "Layouts", ["yabai-binary", "yabai-daemon", "yabai-query"], true, true)
        case .toggleFloat:
            return ("Toggle Float", "Toggle floating for focused window", "Window", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusWest:
            return ("Focus Left", "Focus window west", "Focus", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusEast:
            return ("Focus Right", "Focus window east", "Focus", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusNorth:
            return ("Focus Up", "Focus window north", "Focus", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusSouth:
            return ("Focus Down", "Focus window south", "Focus", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .browserReliefPlaceholder:
            return ("Browser Relief", "One-shot lane relief (planned helper workflow)", "Layouts", ["yabai-binary"], false, true)
        }
    }

    private func trimForUI(_ string: String, maxLength: Int = 220) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }

    private func applyDegradedModeCounters(yabaiWindowTotal: Int?, fallbackWindowTotal: Int?) {
        guard let yabaiWindowTotal, let fallbackWindowTotal else {
            consecutiveMismatchSamples = 0
            consecutiveHealthySamples = 0
            return
        }

        let mismatch = isMaterialMismatch(yabai: yabaiWindowTotal, fallback: fallbackWindowTotal)

        if degradedModeActive {
            if mismatch {
                consecutiveHealthySamples = 0
            } else {
                consecutiveHealthySamples += 1
                if consecutiveHealthySamples >= degradedExitThreshold {
                    degradedModeActive = false
                    consecutiveMismatchSamples = 0
                    consecutiveHealthySamples = 0
                }
            }
        } else {
            if mismatch {
                consecutiveMismatchSamples += 1
                consecutiveHealthySamples = 0
                if consecutiveMismatchSamples >= degradedEnterThreshold {
                    degradedModeActive = true
                    consecutiveHealthySamples = 0
                }
            } else {
                consecutiveMismatchSamples = 0
                consecutiveHealthySamples += 1
            }
        }
    }

    private func isMaterialMismatch(yabai: Int, fallback: Int) -> Bool {
        fallback >= yabai + 2 && fallback >= 3
    }

    private func makeLiveStateSnapshot(from poll: LiveStatePollResult) -> LiveStateSnapshot {
        let forcedFallback = degradedModeActive
        let hasYabaiState = poll.yabaiDisplays != nil && poll.yabaiSpaces != nil && poll.yabaiWindows != nil
        let hasFallback = !poll.fallbackDisplays.isEmpty

        if hasYabaiState && !forcedFallback {
            return LiveStateSnapshot(
                displays: poll.yabaiDisplays ?? [],
                spaces: poll.yabaiSpaces ?? [],
                windows: poll.yabaiWindows ?? [],
                fallbackDisplays: poll.fallbackDisplays,
                source: .yabai,
                lastUpdatedAt: poll.timestamp,
                degraded: false,
                degradedReason: nil,
                yabaiWindowTotal: poll.yabaiWindowTotal,
                fallbackWindowTotal: poll.fallbackWindowTotal,
                consecutiveMismatchSamples: consecutiveMismatchSamples,
                consecutiveHealthySamples: consecutiveHealthySamples,
                lastErrorMessage: poll.errorMessage
            )
        }

        if hasFallback {
            let reason: String
            if forcedFallback {
                reason = "Entered degraded mode after repeated mismatch between yabai window totals and fallback monitor counts."
            } else {
                reason = poll.errorMessage ?? "yabai live state unavailable; showing fallback monitor counts."
            }

            let fallbackDisplaysAsDisplays: [DisplayState] = poll.fallbackDisplays.enumerated().map { idx, item in
                DisplayState(
                    id: Int(item.id) ?? (idx + 1),
                    name: item.name,
                    focused: false,
                    windowCount: item.windowCount,
                    source: .fallback,
                    lastUpdatedAt: item.lastUpdatedAt
                )
            }

            return LiveStateSnapshot(
                displays: fallbackDisplaysAsDisplays,
                spaces: [],
                windows: [],
                fallbackDisplays: poll.fallbackDisplays,
                source: .fallback,
                lastUpdatedAt: poll.timestamp,
                degraded: true,
                degradedReason: reason,
                yabaiWindowTotal: poll.yabaiWindowTotal,
                fallbackWindowTotal: poll.fallbackWindowTotal,
                consecutiveMismatchSamples: consecutiveMismatchSamples,
                consecutiveHealthySamples: consecutiveHealthySamples,
                lastErrorMessage: poll.errorMessage
            )
        }

        if let previous = liveStateSnapshot {
            return LiveStateSnapshot(
                displays: previous.displays.map {
                    DisplayState(
                        id: $0.id,
                        name: $0.name,
                        focused: $0.focused,
                        windowCount: $0.windowCount,
                        source: .stale,
                        lastUpdatedAt: previous.lastUpdatedAt
                    )
                },
                spaces: previous.spaces.map {
                    SpaceState(
                        index: $0.index,
                        label: $0.label,
                        displayId: $0.displayId,
                        focused: $0.focused,
                        visible: $0.visible,
                        layout: $0.layout,
                        windowCount: $0.windowCount,
                        source: .stale,
                        lastUpdatedAt: previous.lastUpdatedAt
                    )
                },
                windows: previous.windows.map {
                    WindowState(
                        id: $0.id,
                        app: $0.app,
                        space: $0.space,
                        display: $0.display,
                        floating: $0.floating,
                        title: $0.title,
                        focused: $0.focused,
                        isVisible: $0.isVisible,
                        isMinimized: $0.isMinimized,
                        isHidden: $0.isHidden,
                        source: .stale,
                        lastUpdatedAt: previous.lastUpdatedAt
                    )
                },
                fallbackDisplays: previous.fallbackDisplays.map {
                    FallbackDisplayCount(
                        id: $0.id,
                        name: $0.name,
                        windowCount: $0.windowCount,
                        source: .stale,
                        lastUpdatedAt: previous.lastUpdatedAt
                    )
                },
                source: .stale,
                lastUpdatedAt: previous.lastUpdatedAt,
                degraded: true,
                degradedReason: poll.errorMessage ?? "No fallback counts available; displaying stale state.",
                yabaiWindowTotal: poll.yabaiWindowTotal ?? previous.yabaiWindowTotal,
                fallbackWindowTotal: poll.fallbackWindowTotal ?? previous.fallbackWindowTotal,
                consecutiveMismatchSamples: consecutiveMismatchSamples,
                consecutiveHealthySamples: consecutiveHealthySamples,
                lastErrorMessage: poll.errorMessage
            )
        }

        return LiveStateSnapshot(
            displays: [],
            spaces: [],
            windows: [],
            fallbackDisplays: [],
            source: .stale,
            lastUpdatedAt: poll.timestamp,
            degraded: true,
            degradedReason: poll.errorMessage ?? "No live or fallback state available yet.",
            yabaiWindowTotal: poll.yabaiWindowTotal,
            fallbackWindowTotal: poll.fallbackWindowTotal,
            consecutiveMismatchSamples: consecutiveMismatchSamples,
            consecutiveHealthySamples: consecutiveHealthySamples,
            lastErrorMessage: poll.errorMessage
        )
    }
}
