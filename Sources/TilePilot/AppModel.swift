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

enum TilePilotActionID: String, CaseIterable, Identifiable {
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

struct TilePilotActionCard: Identifiable {
    let id: TilePilotActionID
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
    private static let pinnedShortcutsDefaultsKey = "TilePilot.pinnedShortcutKeys"
    private static let pinnedDirectionalGroupsDefaultsKey = "TilePilot.pinnedDirectionalGroupIDs"
    private static let showWindowBadgeOverlayDefaultsKey = "TilePilot.showWindowBadgeOverlay"
    private static let showWindowOutlineOverlayDefaultsKey = "TilePilot.showWindowOutlineOverlay"

    @Published private(set) var doctorSnapshot: DoctorSnapshot?
    @Published private(set) var bootstrapSnapshot: SetupBootstrapSnapshot?
    @Published private(set) var liveStateSnapshot: LiveStateSnapshot?
    @Published private(set) var windowBadges: [WindowBadgeState] = []
    @Published private(set) var hoveredWindowIDForBadges: Int?
    @Published private(set) var requestedTilePilotTab: TilePilotTab?
    @Published private(set) var requestedSystemPanelSection: SystemPanelSection?
    @Published private(set) var shortcutEntries: [ShortcutEntry] = []
    @Published private(set) var pinnedShortcutKeys: [String] = UserDefaults.standard.stringArray(forKey: AppModel.pinnedShortcutsDefaultsKey) ?? []
    @Published private(set) var pinnedDirectionalGroupIDs: [String] = UserDefaults.standard.stringArray(forKey: AppModel.pinnedDirectionalGroupsDefaultsKey) ?? []
    @Published private(set) var selectedShortcutStableKey: String?
    @Published private(set) var requestedFileEditorTarget: EditorTarget?
    @Published var managedConfigDraft: String = ""
    @Published private(set) var editableFiles: [EditableConfigFile] = []
    @Published private(set) var selectedEditableFilePath: String?
    @Published private(set) var selectedEditableFileBackups: [ConfigBackupInfo] = []
    @Published private(set) var selectedEditableFileExists = false
    @Published private(set) var selectedEditableFileKind: EditableFileKind = .other
    @Published var editableFileDraft: String = ""
    @Published private(set) var editableFileOriginal: String = ""
    @Published private(set) var editableFileJumpTargetLine: Int?
    @Published private(set) var isRefreshingEditableFiles = false
    @Published private(set) var isLoadingEditableFile = false
    @Published private(set) var isSavingEditableFile = false
    @Published private(set) var isRestoringEditableFile = false
    @Published var filesLastErrorMessage: String?
    @Published var filesLastActionMessage: String?
    @Published private(set) var commandLogs: [CommandLogEntry] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingBootstrap = false
    @Published private(set) var isRefreshingLiveState = false
    @Published private(set) var isRefreshingShortcuts = false
    @Published private(set) var isRefreshingConfig = false
    @Published private(set) var isSavingConfig = false
    @Published private(set) var isRestoringConfig = false
    @Published private(set) var activeActionID: TilePilotActionID?
    @Published private(set) var isLaunchingSetupInstaller = false
    @Published private(set) var isLaunchingScriptingAdditionFix = false
    @Published private(set) var hasAcknowledgedInitialStatus = false
    @Published var actionsLastErrorMessage: String?
    @Published var actionsLastActionMessage: String?
    @Published var lastErrorMessage: String?
    @Published var lastActionMessage: String?
    @Published var lastExportURL: URL?
    @Published var lastSetupInstallerURL: URL?
    @Published var lastScriptingAdditionRepairURL: URL?
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
    @Published var showWindowBadgeOverlay: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.showWindowBadgeOverlayDefaultsKey) == nil {
            return true
        }
        return defaults.bool(forKey: AppModel.showWindowBadgeOverlayDefaultsKey)
    }()
    @Published var showWindowOutlineOverlay: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.showWindowOutlineOverlayDefaultsKey) == nil {
            return false
        }
        return defaults.bool(forKey: AppModel.showWindowOutlineOverlayDefaultsKey)
    }()

    private let doctorService = DoctorService()
    private let bootstrapService = BootstrapService()
    private let yabaiStateService = YabaiStateService()
    private let skhdShortcutService = SkhdShortcutService()
    private let configService = ConfigService()
    private let yabaiRulesConfigService = YabaiRulesConfigService()
    private let configFilesService = ConfigFilesService()
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
    private var scriptHeaderDescriptionCache: [String: String?] = [:]
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

    func requestOpenTilePilotTab(_ tab: TilePilotTab) {
        requestedTilePilotTab = tab
    }

    func requestOpenSystemSection(_ section: SystemPanelSection) {
        requestedSystemPanelSection = section
        requestedTilePilotTab = .system
    }

    func requestOpenFile(path: String, line: Int? = nil) {
        let expanded = NSString(string: path).expandingTildeInPath
        requestedFileEditorTarget = EditorTarget(path: expanded, line: line)
        requestedTilePilotTab = .files
    }

    func consumeRequestedTilePilotTab() -> TilePilotTab? {
        defer { requestedTilePilotTab = nil }
        return requestedTilePilotTab
    }

    func consumeRequestedSystemPanelSection() -> SystemPanelSection? {
        defer { requestedSystemPanelSection = nil }
        return requestedSystemPanelSection
    }

    func consumeRequestedFileEditorTarget() -> EditorTarget? {
        defer { requestedFileEditorTarget = nil }
        return requestedFileEditorTarget
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
        refreshWindowBadges()
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
        scriptHeaderDescriptionCache.removeAll()
        shortcutFilePath = result.filePath
        shortcutParseIssues = result.issues
        await refreshEditableFiles()
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

    func setMouseFollowsFocusEnabled(_ enabled: Bool) {
        windowBehaviorPolicyDraft.mouseFollowsFocusEnabled = enabled
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

    func updateMouseFollowsFocusDraft(_ enabled: Bool) {
        windowBehaviorPolicyDraft.mouseFollowsFocusEnabled = enabled
        recomputeYabaiConfigDiffPreview()
    }

    func disableHoverFocus() {
        windowBehaviorPolicyDraft.hoverFocusMode = .off
        recomputeYabaiConfigDiffPreview()
        saveWindowBehaviorPolicy()
    }

    func disableMouseFollowsFocus() {
        windowBehaviorPolicyDraft.mouseFollowsFocusEnabled = false
        recomputeYabaiConfigDiffPreview()
        saveWindowBehaviorPolicy()
    }

    func toggleWindowBadgeOverlay() {
        showWindowBadgeOverlay.toggle()
        UserDefaults.standard.set(showWindowBadgeOverlay, forKey: AppModel.showWindowBadgeOverlayDefaultsKey)
        refreshWindowBadges()
        lastActionMessage = showWindowBadgeOverlay ? "Window badges enabled." : "Window badges disabled."
        lastErrorMessage = nil
    }

    func toggleWindowOutlineOverlay() {
        showWindowOutlineOverlay.toggle()
        UserDefaults.standard.set(showWindowOutlineOverlay, forKey: AppModel.showWindowOutlineOverlayDefaultsKey)
        refreshWindowBadges()
        lastActionMessage = showWindowOutlineOverlay ? "Window outline overlay enabled." : "Window outline overlay disabled."
        lastErrorMessage = nil
    }

    func tileFocusedWindowNow() {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        setWindowFloating(windowID: focused.id, shouldFloat: false, bringToFrontOnFloat: true)
    }

    func floatFocusedWindowNow() {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        setWindowFloating(windowID: focused.id, shouldFloat: true, bringToFrontOnFloat: true)
    }

    func toggleFocusedWindowTiling() {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        toggleWindowFloating(windowID: focused.id, bringToFrontOnFloat: true)
    }

    func focusWindow(windowID: Int) {
        guard let window = runtimeControllableWindow(windowID: windowID) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.bringWindowToFront(windowID: windowID)
            await MainActor.run {
                self.lastActionMessage = "Focused \(window.app)."
                self.lastErrorMessage = nil
            }
            await self.refreshLiveState()
        }
    }

    func toggleWindowFloating(windowID: Int, bringToFrontOnFloat: Bool = false) {
        guard let window = runtimeControllableWindow(windowID: windowID) else { return }
        setWindowFloating(windowID: windowID, shouldFloat: !window.floating, bringToFrontOnFloat: bringToFrontOnFloat)
    }

    func setWindowFloating(windowID: Int, shouldFloat: Bool, bringToFrontOnFloat: Bool = false) {
        guard let window = runtimeControllableWindow(windowID: windowID) else { return }
        if window.floating == shouldFloat {
            lastActionMessage = shouldFloat ? "\(window.app) is already floating." : "\(window.app) is already tiled."
            lastErrorMessage = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let toggle = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "window", String(windowID), "--toggle", "float"], timeout: 1.5)
            )
            await MainActor.run {
                self.appendCommandLog(from: toggle)
                if !toggle.isSuccess {
                    self.lastErrorMessage = shouldFloat ? "Failed to set window to floating." : "Failed to set window to tiled."
                    self.lastActionMessage = nil
                }
            }
            guard toggle.isSuccess else { return }

            if shouldFloat && bringToFrontOnFloat {
                await self.bringWindowToFront(windowID: windowID)
            }

            await MainActor.run {
                self.lastActionMessage = shouldFloat ? "Window set to floating." : "Window set to tiled."
                self.lastErrorMessage = nil
            }
            await self.refreshLiveState()
        }
    }

    func openWindowBehaviorSettings() {
        requestOpenTilePilotTab(.windowBehavior)
    }

    func openShortcutSource(_ entry: ShortcutEntry) {
        selectShortcut(entry)
        requestOpenFile(path: entry.sourceFile, line: entry.sourceLine)
    }

    var canRunYabaiRuntimeCommands: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return map["yabai-binary"] == .available && map["yabai-daemon"] == .available
    }

    var canRunScriptingAdditionDesktopActions: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return map["scripting-addition"] == .available
    }

    func isScriptingAdditionDesktopShortcut(_ entry: ShortcutEntry) -> Bool {
        entry.command.lowercased().contains("yabai -m window --space")
    }

    var yabaiRuntimeControlDisabledReason: String? {
        guard let snapshot = doctorSnapshot else { return "Open System and run Recheck first." }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0) })
        if map["yabai-binary"]?.status != .available {
            return map["yabai-binary"]?.message ?? "yabai is not installed."
        }
        if map["yabai-daemon"]?.status != .available {
            return map["yabai-daemon"]?.message ?? "yabai is not running."
        }
        return nil
    }

    func displayShortcutCombo(_ entry: ShortcutEntry) -> String {
        let display = parseShortcutComboDisplay(entry.combo)
        if display.symbols == display.words || display.symbols.isEmpty {
            return display.words
        }
        return "\(display.symbols)  \(display.words)"
    }

    func displayShortcutComboWords(_ entry: ShortcutEntry) -> String {
        parseShortcutComboDisplay(entry.combo).words
    }

    func displayShortcutComboSymbols(_ entry: ShortcutEntry) -> String {
        parseShortcutComboDisplay(entry.combo).symbols
    }

    func displayShortcutComboSymbolsSpaced(_ entry: ShortcutEntry) -> String {
        parseShortcutComboDisplay(entry.combo).symbolsSpaced
    }

    func displayShortcutPrimaryKey(_ entry: ShortcutEntry) -> String {
        let trimmed = entry.combo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        let separatorIndex = trimmed.lastIndex(of: "-")
        let keyPartRaw = separatorIndex.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed
        let keyTokens = keyPartRaw
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        let firstToken = (keyTokens.isEmpty ? [keyPartRaw.trimmingCharacters(in: .whitespacesAndNewlines)] : keyTokens).first?.lowercased() ?? ""
        return displayPrimaryKeyToken(lower: firstToken)
    }

    var pinnedShortcutEntries: [ShortcutEntry] {
        var byKey: [String: ShortcutEntry] = [:]
        for entry in shortcutEntries {
            byKey[entry.stableKey] = entry
        }
        return pinnedShortcutKeys.compactMap { byKey[$0] }
    }

    var pinnedDirectionalGroups: [DirectionalShortcutGroup] {
        pinnedDirectionalGroupIDs.compactMap(DirectionalShortcutGroup.init(rawValue:))
    }

    var pinnedDirectionalGroupBindings: [(group: DirectionalShortcutGroup, bindings: [DirectionalShortcutBinding])] {
        pinnedDirectionalGroups.map { group in
            (group: group, bindings: directionalShortcutBindings(for: group))
        }
    }

    func isShortcutPinned(_ entry: ShortcutEntry) -> Bool {
        pinnedShortcutKeys.contains(entry.stableKey)
    }

    func isDirectionalGroupPinned(_ group: DirectionalShortcutGroup) -> Bool {
        pinnedDirectionalGroupIDs.contains(group.rawValue)
    }

    func isShortcutSelected(_ entry: ShortcutEntry) -> Bool {
        selectedShortcutStableKey == entry.stableKey
    }

    func selectShortcut(_ entry: ShortcutEntry) {
        selectedShortcutStableKey = entry.stableKey
    }

    func toggleShortcutPinned(_ entry: ShortcutEntry) {
        selectShortcut(entry)
        if isShortcutPinned(entry) {
            pinnedShortcutKeys.removeAll { $0 == entry.stableKey }
            lastActionMessage = "Removed shortcut from right-click menu."
        } else {
            pinnedShortcutKeys.append(entry.stableKey)
            pinnedShortcutKeys = Array(NSOrderedSet(array: pinnedShortcutKeys)) as? [String] ?? pinnedShortcutKeys
            lastActionMessage = "Pinned shortcut to right-click menu."
        }
        persistPinnedShortcutKeys()
        lastErrorMessage = nil
    }

    func toggleDirectionalGroupPinned(_ group: DirectionalShortcutGroup) {
        if isDirectionalGroupPinned(group) {
            pinnedDirectionalGroupIDs.removeAll { $0 == group.rawValue }
            lastActionMessage = "Removed \(group.menuTitle) from right-click menu."
        } else {
            pinnedDirectionalGroupIDs.append(group.rawValue)
            pinnedDirectionalGroupIDs = Array(NSOrderedSet(array: pinnedDirectionalGroupIDs)) as? [String] ?? pinnedDirectionalGroupIDs
            lastActionMessage = "Pinned \(group.menuTitle) to right-click menu."
        }
        persistPinnedDirectionalGroupIDs()
        lastErrorMessage = nil
    }

    func runShortcut(_ entry: ShortcutEntry) {
        selectShortcut(entry)
        runShortcutCommand(entry.command, shortcutLabel: "\(entry.combo) - \(shortcutExplanation(entry))")
    }

    func runPinnedShortcut(stableKey: String) {
        guard let entry = shortcutEntries.first(where: { $0.stableKey == stableKey }) else {
            lastErrorMessage = "Pinned shortcut is no longer in skhdrc. Open Shortcuts to refresh or unpin it."
            lastActionMessage = nil
            return
        }
        runShortcut(entry)
    }

    func directionalShortcutBindings(for group: DirectionalShortcutGroup) -> [DirectionalShortcutBinding] {
        shortcutEntries.compactMap { entry in
            guard let binding = directionalShortcutBinding(for: entry), binding.group == group else { return nil }
            return binding
        }
        .sorted { lhs, rhs in
            if lhs.direction.sortRank != rhs.direction.sortRank { return lhs.direction.sortRank < rhs.direction.sortRank }
            return lhs.entry.sourceLine < rhs.entry.sourceLine
        }
    }

    func shortcutExplanation(_ entry: ShortcutEntry) -> String {
        shortcutExplanation(combo: entry.combo, command: entry.command, category: entry.category)
    }

    func shortcutTitle(_ entry: ShortcutEntry) -> String {
        shortcutTitle(for: entry)
    }

    func shortcutSecondaryText(_ entry: ShortcutEntry) -> String? {
        let title = shortcutTitle(entry)
        let explanation = shortcutExplanation(entry)
        if normalizedShortcutCopy(title) == normalizedShortcutCopy(explanation) {
            return nil
        }
        return explanation
    }

    func actionButtonLabel(for actionID: TilePilotActionID) -> String {
        actionMeta(for: actionID).buttonLabel
    }

    var editableFileLineCount: Int {
        max(1, editableFileDraft.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
    }

    var selectedEditableFile: EditableConfigFile? {
        guard let path = selectedEditableFilePath else { return nil }
        return editableFiles.first(where: { $0.path == path }) ??
            EditableConfigFile(
                path: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                kind: selectedEditableFileKind,
                exists: selectedEditableFileExists,
                isDiscovered: true
            )
    }

    var isEditableFileDraftDirty: Bool {
        editableFileDraft != editableFileOriginal
    }

    func refreshEditableFiles() async {
        guard !isRefreshingEditableFiles else { return }
        isRefreshingEditableFiles = true
        defer { isRefreshingEditableFiles = false }

        let discovered = await configFilesService.discoverFiles(shortcuts: shortcutEntries)
        editableFiles = discovered

        if let target = consumeRequestedFileEditorTarget() {
            await openEditableFile(path: target.path, line: target.line)
            return
        }

        if let selected = selectedEditableFilePath, discovered.contains(where: { $0.path == selected }) {
            if selectedEditableFilePath == nil || !isEditableFileDraftDirty {
                await loadEditableFile(path: selected, line: nil)
            }
        } else if let first = discovered.first {
            await loadEditableFile(path: first.path, line: nil)
        }
    }

    func handlePendingFileEditorTargetIfNeeded() async {
        guard let target = consumeRequestedFileEditorTarget() else { return }
        await openEditableFile(path: target.path, line: target.line)
    }

    func openEditableFile(path: String, line: Int?) async {
        if !editableFiles.contains(where: { $0.path == path }) {
            let dynamic = EditableConfigFile(
                path: path,
                displayName: URL(fileURLWithPath: path).lastPathComponent,
                kind: inferredEditableFileKind(for: path),
                exists: FileManager.default.fileExists(atPath: path),
                isDiscovered: true
            )
            editableFiles.append(dynamic)
            editableFiles.sort { lhs, rhs in
                editableFileSortRank(lhs) < editableFileSortRank(rhs) ||
                (editableFileSortRank(lhs) == editableFileSortRank(rhs) && lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending)
            }
        }
        await loadEditableFile(path: path, line: line)
    }

    func loadEditableFile(path: String, line: Int?) async {
        guard !isLoadingEditableFile else { return }
        isLoadingEditableFile = true
        defer { isLoadingEditableFile = false }

        do {
            let state = try await configFilesService.loadDocument(path: path)
            selectedEditableFilePath = state.file.path
            selectedEditableFileBackups = state.backups
            selectedEditableFileExists = state.file.exists
            selectedEditableFileKind = state.file.kind
            editableFileDraft = state.content
            editableFileOriginal = state.content
            editableFileJumpTargetLine = line
            filesLastErrorMessage = nil
            if let line {
                filesLastActionMessage = "Editing \(state.file.displayName) at line \(line)."
            }
            editableFiles = editableFiles.map { $0.path == state.file.path ? state.file : $0 }
        } catch {
            filesLastErrorMessage = "Failed to load file: \(error.localizedDescription)"
            filesLastActionMessage = nil
        }
    }

    func updateEditableFileDraft(_ newValue: String) {
        editableFileDraft = newValue
    }

    func consumeEditableFileJumpTargetLine() -> Int? {
        defer { editableFileJumpTargetLine = nil }
        return editableFileJumpTargetLine
    }

    func saveSelectedEditableFile() {
        guard let path = selectedEditableFilePath, !isSavingEditableFile else { return }
        isSavingEditableFile = true
        let content = editableFileDraft
        let kind = selectedEditableFileKind

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isSavingEditableFile = false } }
            do {
                let result = try await self.configFilesService.saveFile(path: path, content: content)
                await MainActor.run {
                    self.selectedEditableFileBackups = result.backups
                    self.selectedEditableFileExists = true
                    self.selectedEditableFileKind = result.file.kind
                    self.editableFileOriginal = content
                    self.editableFiles = self.editableFiles.map { $0.path == path ? result.file : $0 }
                    self.filesLastActionMessage = "Saved \(result.file.displayName)."
                    self.filesLastErrorMessage = nil
                    if kind == .script {
                        self.scriptHeaderDescriptionCache[path] = nil
                    }
                }

                if kind == .skhdrc {
                    await self.runBestEffortSkhdRestartAfterRawFileSave()
                }
                if kind == .skhdrc {
                    await self.refreshShortcuts()
                } else if kind == .yabairc {
                    await self.refreshWindowBehaviorConfig()
                    await self.refreshDoctor()
                    await self.refreshLiveState()
                }
            } catch {
                await MainActor.run {
                    self.filesLastErrorMessage = "Save failed: \(error.localizedDescription)"
                    self.filesLastActionMessage = nil
                }
            }
        }
    }

    func revertSelectedEditableFileDraft() {
        editableFileDraft = editableFileOriginal
        filesLastActionMessage = "Discarded unsaved edits."
        filesLastErrorMessage = nil
    }

    func restoreSelectedEditableFileBackup(_ backup: ConfigBackupInfo? = nil) {
        guard let path = selectedEditableFilePath else { return }
        guard !isRestoringEditableFile else { return }
        guard let backupToRestore = backup ?? selectedEditableFileBackups.first else {
            filesLastErrorMessage = "No backups available for this file."
            filesLastActionMessage = nil
            return
        }

        isRestoringEditableFile = true
        let kind = selectedEditableFileKind
        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isRestoringEditableFile = false } }
            do {
                _ = try await self.configFilesService.restoreBackup(filePath: path, backupPath: backupToRestore.path)
                let reloaded = try await self.configFilesService.loadDocument(path: path)
                await MainActor.run {
                    self.selectedEditableFileBackups = reloaded.backups
                    self.selectedEditableFileExists = reloaded.file.exists
                    self.selectedEditableFileKind = reloaded.file.kind
                    self.editableFileDraft = reloaded.content
                    self.editableFileOriginal = reloaded.content
                    self.editableFiles = self.editableFiles.map { $0.path == path ? reloaded.file : $0 }
                    self.filesLastActionMessage = "Restored backup: \(URL(fileURLWithPath: backupToRestore.path).lastPathComponent)"
                    self.filesLastErrorMessage = nil
                    if kind == .script {
                        self.scriptHeaderDescriptionCache[path] = nil
                    }
                }
                if kind == .skhdrc {
                    await self.runBestEffortSkhdRestartAfterRawFileSave()
                    await self.refreshShortcuts()
                } else if kind == .yabairc {
                    await self.refreshWindowBehaviorConfig()
                    await self.refreshDoctor()
                    await self.refreshLiveState()
                }
            } catch {
                await MainActor.run {
                    self.filesLastErrorMessage = "Restore failed: \(error.localizedDescription)"
                    self.filesLastActionMessage = nil
                }
            }
        }
    }

    func revealSelectedEditableFileInFinder() {
        guard let path = selectedEditableFilePath else { return }
        configFilesService.revealInFinder(path: path)
        filesLastActionMessage = "Revealed file in Finder."
        filesLastErrorMessage = nil
    }

    func restartYabaiAfterRawFileEdit() {
        guard selectedEditableFileKind == .yabairc else { return }
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "--restart-service"], timeout: 2.0),
            successMessage: "Requested yabai service restart."
        )
    }

    func updateManagedConfigDraft(_ newValue: String) {
        managedConfigDraft = newValue
        recomputeConfigDiffPreview()
    }

    func performTilePilotAction(_ actionID: TilePilotActionID) {
        guard activeActionID == nil else { return }
        let availability = actionAvailability(for: actionID)
        guard availability.enabled else {
            let message = availability.disabledReason ?? "This action is unavailable right now."
            actionsLastErrorMessage = message
            actionsLastActionMessage = nil
            lastErrorMessage = message
            lastActionMessage = nil
            return
        }

        actionsLastErrorMessage = nil
        actionsLastActionMessage = nil

        Task { [weak self] in
            guard let self else { return }
            await self.runTilePilotAction(actionID)
        }
    }

    private func persistPinnedShortcutKeys() {
        UserDefaults.standard.set(pinnedShortcutKeys, forKey: AppModel.pinnedShortcutsDefaultsKey)
    }

    private func persistPinnedDirectionalGroupIDs() {
        UserDefaults.standard.set(pinnedDirectionalGroupIDs, forKey: AppModel.pinnedDirectionalGroupsDefaultsKey)
    }

    private func parseShortcutComboDisplay(_ combo: String) -> (symbols: String, symbolsSpaced: String, words: String) {
        let trimmed = combo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "", combo) }

        let separatorIndex = trimmed.lastIndex(of: "-")
        let modifiersPart = separatorIndex.map { String(trimmed[..<$0]) } ?? ""
        let keyPartRaw = separatorIndex.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed

        let modifierTokens = modifiersPart
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let keyTokens = keyPartRaw
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        var modifierWords: [String] = []
        var modifierSymbols: [String] = []
        for token in modifierTokens {
            let lower = token.lowercased()
            switch lower {
            case "alt":
                modifierWords.append("Option")
                modifierSymbols.append("⌥")
            case "cmd":
                modifierWords.append("Command")
                modifierSymbols.append("⌘")
            case "ctrl":
                modifierWords.append("Control")
                modifierSymbols.append("⌃")
            case "shift":
                modifierWords.append("Shift")
                modifierSymbols.append("⇧")
            case "fn":
                modifierWords.append("Fn")
                modifierSymbols.append("fn")
            default:
                modifierWords.append(token)
                modifierSymbols.append(token)
            }
        }

        let keyWordTokens = (keyTokens.isEmpty ? [keyPartRaw.trimmingCharacters(in: .whitespacesAndNewlines)] : keyTokens).filter { !$0.isEmpty }
        let keyWords = keyWordTokens.map { displayKeyWord(lower: $0.lowercased(), original: $0) }
        let keySymbols = keyWordTokens.map { displayKeySymbol(lower: $0.lowercased(), original: $0) }

        let words = (modifierWords + keyWords).joined(separator: " + ")
        let keySymbolPart = keySymbols.joined(separator: keySymbols.count > 1 ? " " : "")
        let symbolTokens = modifierSymbols + (keySymbolPart.isEmpty ? [] : [keySymbolPart])
        let symbols = symbolTokens.joined()
        let symbolsSpaced = symbolTokens.joined(separator: " ")
        return (symbols, symbolsSpaced, words.isEmpty ? combo : words)
    }

    private func displayKeyWord(lower: String, original: String) -> String {
        switch lower {
        case "return", "enter": return "Return"
        case "escape", "esc": return "Escape"
        case "space": return "Space"
        case "tab": return "Tab"
        case "left": return "Left Arrow"
        case "right": return "Right Arrow"
        case "up": return "Up Arrow"
        case "down": return "Down Arrow"
        case "grave", "backtick": return "` / ~"
        case "0x32": return "` / ~"
        default:
            if original.count == 1 { return original.uppercased() }
            return original
        }
    }

    private func displayKeySymbol(lower: String, original: String) -> String {
        switch lower {
        case "return", "enter": return "↩"
        case "escape", "esc": return "⎋"
        case "space": return "␣"
        case "tab": return "⇥"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "grave", "backtick": return "~"
        case "0x32": return "~"
        default:
            if original.count == 1 { return original.uppercased() }
            return original
        }
    }

    private func displayPrimaryKeyToken(lower: String) -> String {
        switch lower {
        case "0x32", "grave", "backtick":
            return "~"
        case "left":
            return "←"
        case "right":
            return "→"
        case "up":
            return "↑"
        case "down":
            return "↓"
        case "space":
            return "Space"
        default:
            return lower.isEmpty ? "?" : lower.uppercased()
        }
    }

    private func directionalShortcutBinding(for entry: ShortcutEntry) -> DirectionalShortcutBinding? {
        let c = entry.command.lowercased()

        if let direction = directionalCardinalDirection(
            from: c,
            west: "yabai -m window --focus west",
            east: "yabai -m window --focus east",
            north: "yabai -m window --focus north",
            south: "yabai -m window --focus south"
        ) {
            return DirectionalShortcutBinding(group: .focusWindow, direction: direction, entry: entry)
        }
        if let direction = directionalCardinalDirection(
            from: c,
            west: "yabai -m window --warp west",
            east: "yabai -m window --warp east",
            north: "yabai -m window --warp north",
            south: "yabai -m window --warp south"
        ) {
            return DirectionalShortcutBinding(group: .moveWindow, direction: direction, entry: entry)
        }
        if let direction = directionalCardinalDirection(
            from: c,
            west: "yabai -m window --swap west",
            east: "yabai -m window --swap east",
            north: "yabai -m window --swap north",
            south: "yabai -m window --swap south"
        ) {
            return DirectionalShortcutBinding(group: .swapWindow, direction: direction, entry: entry)
        }
        if c.contains("yabai -m window --resize left:") { return DirectionalShortcutBinding(group: .resizeWindow, direction: .left, entry: entry) }
        if c.contains("yabai -m window --resize right:") { return DirectionalShortcutBinding(group: .resizeWindow, direction: .right, entry: entry) }
        if c.contains("yabai -m window --resize top:") { return DirectionalShortcutBinding(group: .resizeWindow, direction: .up, entry: entry) }
        if c.contains("yabai -m window --resize bottom:") { return DirectionalShortcutBinding(group: .resizeWindow, direction: .down, entry: entry) }

        return nil
    }

    private func directionalCardinalDirection(
        from command: String,
        west: String,
        east: String,
        north: String,
        south: String
    ) -> DirectionalShortcutDirection? {
        if command.contains(north) { return .up }
        if command.contains(west) { return .left }
        if command.contains(south) { return .down }
        if command.contains(east) { return .right }
        return nil
    }

    private func runShortcutCommand(_ commandText: String, shortcutLabel: String) {
        Task { [weak self] in
            guard let self else { return }
            let result = await self.doctorService.runSupportCommand(
                ShellCommand("/bin/zsh", ["-lc", commandText], timeout: 3.0)
            )
            await MainActor.run {
                let logEntry = CommandLogEntry(
                    id: UUID(),
                    command: "shortcut: \(shortcutLabel)",
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
                    self.lastActionMessage = "Ran shortcut: \(shortcutLabel)"
                    self.lastErrorMessage = nil
                    Task {
                        await self.refreshLiveState()
                    }
                } else {
                    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastErrorMessage = stderr.isEmpty ? "Shortcut command failed: \(shortcutLabel)" : "Shortcut failed: \(stderr)"
                    self.lastActionMessage = nil
                }
            }
        }
    }

    private func shortcutExplanation(combo: String, command: String, category: String) -> String {
        let c = command.lowercased()

        if c.contains("grid-tiling-floating.sh") {
            return "Applies grid tiling on the current desktop and keeps those windows floating."
        }
        if c.contains("grid-tiling-auto-tiled.sh") {
            return "Applies grid tiling on the current desktop, then returns to real auto-tiling (BSP)."
        }
        if c.contains("grid-pack-toggle.sh") {
            return "Legacy grid tiling toggle helper."
        }

        if c.contains("yabai -m window --space"), c.contains("yabai -m space --focus") {
            if let target = firstInteger(after: "--space", in: c) ?? firstInteger(after: "--focus", in: c) {
                return "Moves the focused window to Desktop \(target), then switches to Desktop \(target)."
            }
            return "Moves the focused window to another desktop, then switches there."
        }
        if c.contains("yabai -m window --space") {
            if let target = firstInteger(after: "--space", in: c) {
                return "Moves the focused window to Desktop \(target)."
            }
            return "Moves the focused window to another desktop."
        }
        if c.contains("yabai -m space --focus"), let target = firstInteger(after: "--focus", in: c) {
            return "Switches to Desktop \(target)."
        }

        if c.contains("yabai -m window --toggle float") {
            return "Switches the focused window between tiled and floating."
        }
        if c.contains("yabai -m window --focus west") { return "Moves focus to the window on the left." }
        if c.contains("yabai -m window --focus east") { return "Moves focus to the window on the right." }
        if c.contains("yabai -m window --focus north") { return "Moves focus to the window above." }
        if c.contains("yabai -m window --focus south") { return "Moves focus to the window below." }
        if c.contains("yabai -m window --swap west") { return "Swaps the focused window with the window on the left." }
        if c.contains("yabai -m window --swap east") { return "Swaps the focused window with the window on the right." }
        if c.contains("yabai -m window --swap north") { return "Swaps the focused window with the window above." }
        if c.contains("yabai -m window --swap south") { return "Swaps the focused window with the window below." }
        if c.contains("yabai -m window --warp west") { return "Moves the focused window into the left tile position." }
        if c.contains("yabai -m window --warp east") { return "Moves the focused window into the right tile position." }
        if c.contains("yabai -m window --warp north") { return "Moves the focused window into the upper tile position." }
        if c.contains("yabai -m window --warp south") { return "Moves the focused window into the lower tile position." }
        if c.contains("yabai -m window --resize left:") { return "Resizes the focused window from the left edge (left)." }
        if c.contains("yabai -m window --resize right:") { return "Resizes the focused window from the right edge (right)." }
        if c.contains("yabai -m window --resize top:") { return "Resizes the focused window from the top edge (up)." }
        if c.contains("yabai -m window --resize bottom:") { return "Resizes the focused window from the bottom edge (down)." }
        if c.contains("yabai -m window --resize") { return "Resizes the focused window." }
        if c.contains("yabai -m space --balance") { return "Balances the tiles on the current desktop." }
        if c.contains("yabai -m space --rotate") {
            if let degrees = firstInteger(after: "--rotate", in: c) {
                return "Rotates the current desktop layout by \(degrees) degrees."
            }
            return "Rotates the current desktop layout."
        }
        if c.contains("yabai -m space --layout bsp") { return "Sets the current desktop layout to tiled splits." }
        if c.contains("yabai -m space --layout stack") { return "Sets the current desktop layout to a stack." }
        if c.contains("yabai -m space --focus prev") { return "Switches to the previous desktop." }
        if c.contains("yabai -m space --focus next") { return "Switches to the next desktop." }
        if c.contains("yabai -m space --focus") { return "Switches to a specific desktop." }
        if c.contains("yabai -m display --focus") { return "Moves focus to another display." }
        if c.contains("yabai -m window --display") { return "Sends the focused window to another display." }
        if c.contains("open -a ") || c.hasPrefix("open ") {
            return "Opens an app or file."
        }
        if c.contains("osascript") {
            return "Runs an AppleScript automation."
        }
        if c.contains("skhd -k") {
            return "Triggers another keyboard sequence."
        }
        if let scriptDescription = scriptShortcutDescription(command: command) {
            return scriptDescription
        }

        switch category {
        case "Windows":
            return "Runs a window shortcut from your skhd config."
        case "Spaces":
            return "Runs a desktop shortcut from your skhd config."
        case "Displays":
            return "Runs a display shortcut from your skhd config."
        case "Apps":
            return "Opens an app or file."
        case "Macros":
            return "Runs a helper macro from your skhd config."
        default:
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "No command is configured on this line." }
            let snippet = trimmed.count > 72 ? String(trimmed.prefix(69)) + "..." : trimmed
            return "Runs: \(snippet)"
        }
    }

    private func scriptShortcutDescription(command: String) -> String? {
        guard let path = scriptPath(from: command) else { return nil }
        if let header = scriptDescriptionFromHeader(path: path) {
            return header
        }
        return scriptFallbackDescription(from: path)
    }

    private func firstInteger(after flag: String, in text: String) -> Int? {
        guard let range = text.range(of: flag) else { return nil }
        let suffix = text[range.upperBound...]
        let digits = suffix.firstMatch(of: /[^\d]*(\d+)/)?.1
        if let digits {
            return Int(String(digits))
        }
        return nil
    }

    func exportDiagnostics() {
        guard let snapshot = doctorSnapshot else {
            lastErrorMessage = "Run System Recheck before exporting diagnostics."
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
            lastErrorMessage = "Run System Recheck before copying a status summary."
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

    func runScriptingAdditionRepairInTerminal() {
        guard !isLaunchingScriptingAdditionFix else { return }
        acknowledgeInitialStatusIfNeeded()
        isLaunchingScriptingAdditionFix = true

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isLaunchingScriptingAdditionFix = false } }

            do {
                let scriptURL = try self.bootstrapService.prepareScriptingAdditionRepairScript()
                let openResult = await self.doctorService.runSupportCommand(
                    ShellCommand("/usr/bin/open", ["-a", "Terminal", scriptURL.path], timeout: 3.0)
                )

                await MainActor.run {
                    self.lastScriptingAdditionRepairURL = scriptURL
                    self.appendCommandLog(from: openResult)
                    if openResult.isSuccess {
                        self.lastActionMessage = "Opened scripting addition repair in Terminal."
                        self.lastErrorMessage = nil
                    } else {
                        self.lastErrorMessage = "Failed to open scripting addition repair in Terminal. Try opening \(scriptURL.path) manually."
                        self.lastActionMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Failed to prepare scripting addition repair script: \(error.localizedDescription)"
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

    func openMissionControlKeyboardShortcuts() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?KeyboardShortcutsTab",
            "x-apple.systempreferences:com.apple.preference.keyboard",
            "x-apple.systempreferences:",
        ])
    }

    func openLoginItemsSettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings",
            "x-apple.systempreferences:",
        ])
    }

    func enableStartAtLogon() {
        acknowledgeInitialStatusIfNeeded()

        let fm = FileManager.default
        let launchAgentsDirectory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDirectory
            .appendingPathComponent(BootstrapService.startAtLogonLaunchAgentFileName)

        do {
            try fm.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            let plist = startAtLogonLaunchAgentPlist()
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            lastActionMessage = "Enabled start at logon."
            lastErrorMessage = nil
            Task { [weak self] in
                await self?.refreshBootstrapSetup()
            }
        } catch {
            lastErrorMessage = "Failed to enable start at logon: \(error.localizedDescription)"
            lastActionMessage = nil
        }
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

    private func startAtLogonLaunchAgentPlist() -> String {
        let appPath = Bundle.main.bundlePath
        let escapedAppPath = xmlEscaped(appPath)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(BootstrapService.startAtLogonLaunchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(escapedAppPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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
            // Keep the advanced scripting-addition item at the end of the essentials list.
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

    var windowBehaviorSummaryLine: String {
        let mode = windowBehaviorPolicyDraft.manualTilingModeEnabled ? "Manual tiling ON" : "Manual tiling OFF"
        let hover = "Hover focus: \(windowBehaviorPolicyDraft.hoverFocusMode.displayName)"
        let cursor = "Cursor follows focus: \(windowBehaviorPolicyDraft.mouseFollowsFocusEnabled ? "On" : "Off")"
        return "\(mode) · \(hover) · \(cursor)"
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

    func refreshWindowBadges() {
        guard let snapshot = liveStateSnapshot else {
            windowBadges = []
            hoveredWindowIDForBadges = nil
            return
        }
        guard snapshot.source == .yabai, !snapshot.degraded else {
            windowBadges = []
            hoveredWindowIDForBadges = nil
            return
        }

        let candidates = snapshot.windows.filter { window in
            window.isVisible && !window.isMinimized && !window.isHidden && window.frameW > 40 && window.frameH > 24
        }
        guard !candidates.isEmpty else {
            windowBadges = []
            hoveredWindowIDForBadges = nil
            return
        }

        let activeSpaceIndex: Int? =
            candidates.first(where: \.focused)?.space
            ?? snapshot.spaces.first(where: \.focused)?.index
            ?? snapshot.spaces.first(where: \.visible)?.index
        let activeCandidates: [WindowState]
        if let activeSpaceIndex {
            activeCandidates = candidates.filter { $0.space == activeSpaceIndex }
        } else {
            activeCandidates = candidates
        }

        guard showWindowBadgeOverlay || showWindowOutlineOverlay else {
            windowBadges = []
            hoveredWindowIDForBadges = nil
            return
        }
        hoveredWindowIDForBadges = nil
        let selected = activeCandidates.sorted { lhs, rhs in
            if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
            if lhs.app != rhs.app { return lhs.app.localizedCaseInsensitiveCompare(rhs.app) == .orderedAscending }
            return lhs.id < rhs.id
        }

        windowBadges = selected.map { window in
            WindowBadgeState(
                windowID: window.id,
                pid: window.pid,
                app: window.app,
                title: window.title,
                isFloating: window.floating,
                isFocused: window.focused,
                frameX: window.frameX,
                frameY: window.frameY,
                frameW: window.frameW,
                frameH: window.frameH
            )
        }
    }

    func updateHoveredWindowForBadges(candidates: [WindowState]? = nil) {
        guard let snapshot = liveStateSnapshot, snapshot.source == .yabai, !snapshot.degraded else {
            hoveredWindowIDForBadges = nil
            return
        }
        let windows = candidates ?? snapshot.windows.filter { $0.isVisible && !$0.isMinimized && !$0.isHidden }
        guard !windows.isEmpty else {
            hoveredWindowIDForBadges = nil
            return
        }

        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens

        let hovered = windows
            .filter { containsMouse(mouse, in: $0, screens: screens) }
            .sorted { lhs, rhs in
                if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                let lhsArea = lhs.frameW * lhs.frameH
                let rhsArea = rhs.frameW * rhs.frameH
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return lhs.id < rhs.id
            }
            .first?
            .id

        hoveredWindowIDForBadges = hovered
    }

    var shouldShowWindowBehaviorRecommendation: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let capabilityByKey = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return capabilityByKey["yabai-binary"] == .available && !yabaiConfigHasManagedSection
    }

    var advancedChecklistItems: [DoctorChecklistItem] {
        checklistItems.filter { !$0.isCore }
    }

    private var hasObservedScriptingAdditionRuntimeFailure: Bool {
        commandLogs.prefix(100).contains { entry in
            let haystack = (entry.stderrSnippet + " " + entry.stdoutSnippet).lowercased()
            return haystack.contains("scripting-addition")
        }
    }

    var actionCards: [TilePilotActionCard] {
        TilePilotActionID.allCases
            .filter { $0 != .browserReliefPlaceholder }
            .map { actionID in
            let meta = actionMeta(for: actionID)
            let availability = actionAvailability(for: actionID)
            return TilePilotActionCard(
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

    var quickActionCards: [TilePilotActionCard] {
        actionCards.filter { ["Layouts", "Window"].contains($0.category) && $0.id != .browserReliefPlaceholder }
    }

    var unifiedControlRows: [UnifiedControlRow] {
        var byIntent: [String: UnifiedControlRow] = [:]
        var actionIDsBoundToShortcut: Set<TilePilotActionID> = []

        for entry in shortcutEntries {
            let intent = shortcutIntentKey(for: entry)
            let group = unifiedGroup(for: entry)
            let matchingAction = matchingActionID(forShortcutIntentKey: intent)
            if let matchingAction {
                actionIDsBoundToShortcut.insert(matchingAction)
            }

            let row = UnifiedControlRow(
                id: "shortcut-\(entry.stableKey)",
                group: group,
                title: shortcutTitle(for: entry),
                description: shortcutExplanation(entry),
                shortcutEntry: entry,
                actionID: matchingAction,
                secondaryActionIDs: [],
                isExperimental: group == .experimental,
                disabledReason: matchingAction.flatMap { actionCard(for: $0)?.disabledReason },
                intentKey: intent
            )
            byIntent[intent] = row
        }

        for card in actionCards {
            let intent = actionIntentKey(for: card.id)
            if var existing = byIntent[intent] {
                if existing.actionID == nil {
                    existing = UnifiedControlRow(
                        id: existing.id,
                        group: existing.group,
                        title: existing.title,
                        description: existing.description,
                        shortcutEntry: existing.shortcutEntry,
                        actionID: card.id,
                        secondaryActionIDs: existing.secondaryActionIDs,
                        isExperimental: existing.isExperimental,
                        disabledReason: card.disabledReason,
                        intentKey: existing.intentKey
                    )
                    byIntent[intent] = existing
                } else if existing.actionID != card.id {
                    var secondary = existing.secondaryActionIDs
                    secondary.append(card.id)
                    var dedupedSecondary: [TilePilotActionID] = []
                    for actionID in secondary where !dedupedSecondary.contains(actionID) {
                        dedupedSecondary.append(actionID)
                    }
                    existing = UnifiedControlRow(
                        id: existing.id,
                        group: existing.group,
                        title: existing.title,
                        description: existing.description,
                        shortcutEntry: existing.shortcutEntry,
                        actionID: existing.actionID,
                        secondaryActionIDs: dedupedSecondary,
                        isExperimental: existing.isExperimental,
                        disabledReason: existing.disabledReason ?? card.disabledReason,
                        intentKey: existing.intentKey
                    )
                    byIntent[intent] = existing
                }
                continue
            }

            if actionIDsBoundToShortcut.contains(card.id) {
                continue
            }

            let group = unifiedGroup(forActionCategory: card.category)
            byIntent[intent] = UnifiedControlRow(
                id: "action-\(card.id.rawValue)",
                group: group,
                title: card.title,
                description: card.subtitle,
                shortcutEntry: nil,
                actionID: card.id,
                secondaryActionIDs: [],
                isExperimental: group == .experimental,
                disabledReason: card.disabledReason,
                intentKey: intent
            )
        }

        return byIntent.values.sorted { lhs, rhs in
            if lhs.group.sortRank != rhs.group.sortRank { return lhs.group.sortRank < rhs.group.sortRank }
            if lhs.title != rhs.title { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    func filteredUnifiedControlRows(query: String) -> [UnifiedControlRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return unifiedControlRows }
        return unifiedControlRows.filter { row in
            row.title.lowercased().contains(q) ||
                row.description.lowercased().contains(q) ||
                row.shortcutEntry?.combo.lowercased().contains(q) == true ||
                row.shortcutEntry?.command.lowercased().contains(q) == true ||
                row.group.title.lowercased().contains(q)
        }
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

    func toggleAppDefaultTilingBehavior(for appName: String) {
        let trimmed = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let currentDefault = appTilingBehavior(for: trimmed)
        let next: AppTilingBehavior
        switch currentDefault {
        case .neverTile:
            next = .alwaysTile
        case .alwaysTile:
            next = .neverTile
        case .useDefault:
            // Toggle against current global default shown in Overview.
            next = windowBehaviorPolicyDraft.manualTilingModeEnabled ? .alwaysTile : .neverTile
        }
        setAppTilingBehavior(next, for: trimmed)
        saveWindowBehaviorPolicy()
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
            items.append(scriptingAdditionChecklist(from: item))
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

    private func scriptingAdditionChecklist(from capability: CapabilityState) -> DoctorChecklistItem {
        if hasObservedScriptingAdditionRuntimeFailure {
            var remediation = capability.remediationSteps
            if !remediation.contains(where: { $0.localizedCaseInsensitiveContains("repair") || $0.localizedCaseInsensitiveContains("install") }) {
                remediation.insert("Use “Fix Scripting Addition” to reinstall/load yabai’s scripting addition in Terminal.", at: 0)
            }
            return DoctorChecklistItem(
                title: "yabai desktop control (scripting addition)",
                isCore: true,
                status: .degraded,
                detail: "Your yabai-based desktop shortcuts are failing because the scripting addition is unavailable. macOS can still handle desktop switching with Mission Control keyboard shortcuts.",
                remediation: remediation
            )
        }

        var detail = capability.message
        if capability.status == .available {
            detail = "yabai desktop switching and move-window shortcuts should be available."
        } else if capability.status == .unknown {
            detail = "Moving windows between desktops (and some desktop controls) may require the yabai scripting addition on this setup. Plain desktop switching can use macOS Mission Control shortcuts."
        }

        var remediation = capability.remediationSteps
        if capability.status != .available {
            remediation.insert("Use “Fix Scripting Addition” to reinstall/load yabai’s scripting addition in Terminal.", at: 0)
        }

        return DoctorChecklistItem(
            title: "yabai desktop control (scripting addition)",
            isCore: true,
            status: capability.status,
            detail: detail,
            remediation: Array(NSOrderedSet(array: remediation)) as? [String] ?? remediation
        )
    }

    private func mappedSystemStatus(from setupState: SetupCheckState?) -> SystemCheckStatus? {
        guard let setupState else { return nil }
        switch setupState {
        case .installed:
            return .good
        case .unknown:
            return .notice
        case .warning:
            return .warning
        case .missing:
            return .error
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

    private func currentPollingIntervalSeconds() -> Double {
        let anyVisibleNonSettingsWindow = NSApp.windows.contains { window in
            window.isVisible && window.title == "TilePilot"
        }
        if showWindowBadgeOverlay || showWindowOutlineOverlay {
            return anyVisibleNonSettingsWindow ? 0.8 : 1.8
        }
        return anyVisibleNonSettingsWindow ? 1.8 : 6.0
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

    private func inferredEditableFileKind(for path: String) -> EditableFileKind {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded == NSString(string: "~/.config/yabai/yabairc").expandingTildeInPath { return .yabairc }
        if expanded == NSString(string: "~/.config/skhd/skhdrc").expandingTildeInPath { return .skhdrc }
        if URL(fileURLWithPath: expanded).pathExtension.lowercased() == "sh" { return .script }
        return .other
    }

    private func editableFileSortRank(_ file: EditableConfigFile) -> Int {
        switch file.kind {
        case .yabairc: return 0
        case .skhdrc: return 1
        case .script: return 2
        case .other: return 3
        }
    }

    private func applyWindowBehaviorRuntime(previous: ManagedWindowBehaviorPolicy, current: ManagedWindowBehaviorPolicy) async {
        var configApplyFailed = false
        let configCommands: [ShellCommand] = [
            ShellCommand("/usr/bin/env", ["yabai", "-m", "config", "focus_follows_mouse", current.hoverFocusMode.rawValue], timeout: 1.5),
            ShellCommand("/usr/bin/env", ["yabai", "-m", "config", "mouse_follows_focus", current.mouseFollowsFocusEnabled ? "on" : "off"], timeout: 1.5),
        ]
        for command in configCommands {
            let result = await doctorService.runSupportCommand(command)
            if !result.isSuccess {
                configApplyFailed = true
            }
            await MainActor.run {
                self.appendCommandLog(from: result)
                if !result.isSuccess {
                    self.lastActionMessage = "Saved settings, but runtime apply may require restarting yabai."
                }
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
                if !ruleApplyFailed && !configApplyFailed {
                    self.lastActionMessage = "Manual Tiling Mode enabled. Existing windows stay as-is; new windows should stop auto-tiling."
                    self.lastErrorMessage = nil
                } else if self.lastErrorMessage == nil {
                    self.lastErrorMessage = "Saved settings, but some live yabai rules did not apply. Restart yabai if behavior looks wrong."
                }
            } else {
                if !ruleApplyFailed && !configApplyFailed {
                    self.lastActionMessage = "Window behavior updated."
                    self.lastErrorMessage = nil
                } else if self.lastErrorMessage == nil {
                    self.lastErrorMessage = "Saved settings, but some runtime updates did not apply. Restart yabai if behavior looks wrong."
                }
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

    private func runtimeControllableWindow(windowID: Int) -> WindowState? {
        guard canRunYabaiRuntimeCommands else {
            lastErrorMessage = yabaiRuntimeControlDisabledReason ?? "Window controls are unavailable right now."
            lastActionMessage = nil
            return nil
        }
        guard let window = liveStateSnapshot?.windows.first(where: { $0.id == windowID }) else {
            lastErrorMessage = "Window is no longer available."
            lastActionMessage = nil
            return nil
        }
        return window
    }

    private func containsMouse(_ mouse: NSPoint, in window: WindowState, screens: [NSScreen]) -> Bool {
        let rect = convertTopOriginRectToAppKit(CGRect(x: window.frameX, y: window.frameY, width: window.frameW, height: window.frameH), screens: screens)
        return rect.contains(mouse)
    }

    private func convertTopOriginRectToAppKit(_ rect: CGRect, screens: [NSScreen]) -> CGRect {
        guard !screens.isEmpty else { return rect }
        let referenceMaxY = screens.first(where: { screen in
            abs(screen.frame.minX) < 0.5 && abs(screen.frame.minY) < 0.5
        })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? screens.map(\.frame.maxY).min()
            ?? rect.maxY
        return CGRect(
            x: rect.origin.x,
            y: referenceMaxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
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

    private func runBestEffortSkhdRestartAfterRawFileSave() async {
        let result = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["skhd", "--restart-service"], timeout: 2.0)
        )
        await MainActor.run {
            self.appendCommandLog(from: result)
            if result.isSuccess {
                self.filesLastActionMessage = "Saved file and requested skhd restart."
                self.filesLastErrorMessage = nil
            } else {
                let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                self.filesLastActionMessage = "Saved file. skhd restart is best effort and may require manual restart."
                if !stderr.isEmpty {
                    self.filesLastErrorMessage = "skhd restart failed: \(trimForUI(stderr))"
                }
            }
        }
    }

    private func runTilePilotAction(_ actionID: TilePilotActionID) async {
        activeActionID = actionID
        defer { activeActionID = nil }

        let beforeSignature = liveStateSignature()
        let commands = actionCommands(for: actionID)
        guard !commands.isEmpty else {
            actionsLastErrorMessage = "This action is not available yet."
            actionsLastActionMessage = nil
            lastErrorMessage = actionsLastErrorMessage
            lastActionMessage = nil
            return
        }

        for command in commands {
            let result = await doctorService.runSupportCommand(command)
            appendCommandLog(from: result)
            if !result.isSuccess {
                actionsLastErrorMessage = actionMeta(for: actionID).title + " didn’t work."
                if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    actionsLastErrorMessage = actionFailureMessage(for: actionID, commandResult: result)
                }
                actionsLastActionMessage = nil
                lastErrorMessage = actionsLastErrorMessage
                lastActionMessage = nil
                return
            }
        }

        await refreshLiveState()

        let afterSignature = liveStateSignature()
        if beforeSignature != nil, beforeSignature == afterSignature {
            actionsLastActionMessage = "\(actionMeta(for: actionID).title) ran, but nothing visibly changed."
        } else {
            actionsLastActionMessage = "\(actionMeta(for: actionID).title) completed."
        }
        actionsLastErrorMessage = nil
        lastActionMessage = actionsLastActionMessage
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

    private func actionCommands(for actionID: TilePilotActionID) -> [ShellCommand] {
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

    private func actionAvailability(for actionID: TilePilotActionID) -> (enabled: Bool, disabledReason: String?) {
        let meta = actionMeta(for: actionID)

        if actionID == .browserReliefPlaceholder {
            return (false, "This action is not available yet.")
        }

        guard let doctor = doctorSnapshot else {
            return (false, "Open System and run Recheck first.")
        }

        let capabilityByKey = Dictionary(uniqueKeysWithValues: doctor.capabilities.map { ($0.key, $0) })
        for key in meta.requiredCapabilities {
            guard let capability = capabilityByKey[key] else {
                return (false, "Run System Recheck, then try this action.")
            }
            if capability.status == .blocked || capability.status == .unsupported {
                return (false, userFacingDisabledReason(forCapabilityKey: key, capability: capability))
            }
            if key == "yabai-query", capability.status != .available {
                return (false, userFacingDisabledReason(forCapabilityKey: key, capability: capability))
            }
            if key == "yabai-daemon", capability.status != .available {
                return (false, userFacingDisabledReason(forCapabilityKey: key, capability: capability))
            }
            if key == "yabai-binary", capability.status != .available {
                return (false, userFacingDisabledReason(forCapabilityKey: key, capability: capability))
            }
        }

        if meta.requiresLiveState {
            guard let snapshot = liveStateSnapshot else {
                return (false, "Overview is still loading. Try again in a moment.")
            }
            if snapshot.source == .stale {
                return (false, "TilePilot lost the live window view. Open Overview and wait for it to recover.")
            }
        }

        if meta.disableInDegradedMode {
            if let snapshot = liveStateSnapshot, snapshot.degraded {
                return (false, "This layout action is temporarily unavailable because TilePilot is using a reduced-precision view.")
            }
        }

        if activeActionID != nil {
            return (false, "Another action is already running.")
        }

        return (true, nil)
    }

    func actionCard(for actionID: TilePilotActionID) -> TilePilotActionCard? {
        actionCards.first(where: { $0.id == actionID })
    }

    func actionCard(forShortcut entry: ShortcutEntry) -> TilePilotActionCard? {
        guard let actionID = matchingActionID(forShortcutIntentKey: shortcutIntentKey(for: entry)) else { return nil }
        return actionCard(for: actionID)
    }

    private func matchingActionID(forShortcutIntentKey intentKey: String) -> TilePilotActionID? {
        TilePilotActionID.allCases.first { actionIntentKey(for: $0) == intentKey }
    }

    private func actionIntentKey(for actionID: TilePilotActionID) -> String {
        switch actionID {
        case .balanceSpace:
            return "space-balance"
        case .layoutBSPAndBalance:
            return "space-layout-bsp-balance"
        case .layoutStack:
            return "space-layout-stack"
        case .toggleFloat:
            return "window-toggle-float"
        case .focusWest:
            return "window-focus-west"
        case .focusEast:
            return "window-focus-east"
        case .focusNorth:
            return "window-focus-north"
        case .focusSouth:
            return "window-focus-south"
        case .browserReliefPlaceholder:
            return "browser-relief"
        }
    }

    private func shortcutIntentKey(for entry: ShortcutEntry) -> String {
        let c = entry.command.lowercased()

        if c.contains("yabai -m window --space"), c.contains("yabai -m space --focus"),
           let target = firstInteger(after: "--space", in: c) ?? firstInteger(after: "--focus", in: c) {
            return "window-space-focus-\(target)"
        }
        if c.contains("yabai -m window --space"),
           let target = firstInteger(after: "--space", in: c) {
            return "window-space-\(target)"
        }
        if c.contains("yabai -m space --focus"),
           let target = firstInteger(after: "--focus", in: c) {
            return "space-focus-\(target)"
        }
        if c.contains("yabai -m window --toggle float") { return "window-toggle-float" }
        if c.contains("yabai -m window --focus west") { return "window-focus-west" }
        if c.contains("yabai -m window --focus east") { return "window-focus-east" }
        if c.contains("yabai -m window --focus north") { return "window-focus-north" }
        if c.contains("yabai -m window --focus south") { return "window-focus-south" }
        if c.contains("yabai -m window --warp west") { return "window-warp-west" }
        if c.contains("yabai -m window --warp east") { return "window-warp-east" }
        if c.contains("yabai -m window --warp north") { return "window-warp-north" }
        if c.contains("yabai -m window --warp south") { return "window-warp-south" }
        if c.contains("yabai -m window --resize left:") { return "window-resize-left" }
        if c.contains("yabai -m window --resize right:") { return "window-resize-right" }
        if c.contains("yabai -m window --resize top:") { return "window-resize-up" }
        if c.contains("yabai -m window --resize bottom:") { return "window-resize-down" }
        if c.contains("yabai -m space --layout bsp"), c.contains("yabai -m space --balance") { return "space-layout-bsp-balance" }
        if c.contains("yabai -m space --layout stack") { return "space-layout-stack" }
        if c.contains("yabai -m space --balance") { return "space-balance" }
        if c.contains("yabai -m space --rotate") {
            if let degrees = firstInteger(after: "--rotate", in: c) {
                return "space-rotate-\(degrees)"
            }
            return "space-rotate"
        }
        if c.contains("yabai -m window --swap west") { return "window-swap-west" }
        if c.contains("yabai -m window --swap east") { return "window-swap-east" }
        if c.contains("yabai -m window --swap north") { return "window-swap-north" }
        if c.contains("yabai -m window --swap south") { return "window-swap-south" }
        if c.contains("yabai -m display --focus") { return "display-focus" }
        if c.contains("yabai -m window --display") { return "window-display" }
        if c.contains("skhd -k") { return "macro-\(entry.stableKey)" }
        if c.contains("osascript") { return "automation-\(entry.stableKey)" }

        return "shortcut-\(entry.stableKey)"
    }

    private func unifiedGroup(for entry: ShortcutEntry) -> UnifiedControlGroup {
        let c = entry.command.lowercased()

        if c.contains("yabai -m window --space") {
            return .experimental
        }
        if c.contains("yabai -m space --focus") {
            return .desktops
        }
        if c.contains("yabai -m window --warp") {
            return .windowPlacement
        }
        if c.contains("yabai -m window --resize") {
            return .windowSize
        }
        if c.contains("yabai -m window --toggle float") ||
            c.contains("yabai -m space --balance") ||
            c.contains("yabai -m space --layout") ||
            c.contains("yabai -m space --rotate") ||
            c.contains("yabai -m window --swap") {
            return .tilingLayout
        }
        if c.contains("yabai -m window --focus") {
            return .focus
        }
        if c.contains("yabai -m display") {
            return .displays
        }
        if c.contains("osascript") || c.contains("skhd -k") {
            return .automation
        }

        if let first = c.split(whereSeparator: \.isWhitespace).first {
            let token = String(first)
            if token.hasPrefix("/") || token.hasPrefix("~/") || token.hasPrefix("./") {
                return .helpersScripts
            }
        }
        if c.hasPrefix("open ") || c.contains(" open ") {
            return .apps
        }
        if entry.category == "Spaces" { return .desktops }
        if entry.category == "Windows" { return .tilingLayout }
        return .other
    }

    private func unifiedGroup(forActionCategory category: String) -> UnifiedControlGroup {
        switch category {
        case "Layouts":
            return .tilingLayout
        case "Window":
            return .windowPlacement
        case "Focus":
            return .focus
        default:
            return .other
        }
    }

    private func shortcutTitle(for entry: ShortcutEntry) -> String {
        let c = entry.command.lowercased()

        if c.contains("grid-tiling-floating.sh") {
            return "Grid Tiling (Floating)"
        }
        if c.contains("grid-tiling-auto-tiled.sh") {
            return "Grid -> Auto-Tile (BSP)"
        }
        if c.contains("grid-pack-toggle.sh") {
            return "Grid Tiling (Legacy Toggle)"
        }
        if c.contains("auto-layout-current-desktop.sh") || c.contains("readable-current-space.sh") {
            return "Auto Layout (Current Desktop)"
        }

        if c.contains("yabai -m window --space"), c.contains("yabai -m space --focus"),
           let target = firstInteger(after: "--space", in: c) ?? firstInteger(after: "--focus", in: c) {
            return "Move Window to Desktop \(target)"
        }
        if c.contains("yabai -m space --focus"),
           let target = firstInteger(after: "--focus", in: c) {
            return "Go to Desktop \(target)"
        }
        if c.contains("yabai -m window --focus west") { return "Focus Left" }
        if c.contains("yabai -m window --focus east") { return "Focus Right" }
        if c.contains("yabai -m window --focus north") { return "Focus Up" }
        if c.contains("yabai -m window --focus south") { return "Focus Down" }
        if c.contains("yabai -m window --warp west") { return "Move Window Left" }
        if c.contains("yabai -m window --warp east") { return "Move Window Right" }
        if c.contains("yabai -m window --warp north") { return "Move Window Up" }
        if c.contains("yabai -m window --warp south") { return "Move Window Down" }
        if c.contains("yabai -m window --resize left:") { return "Resize Left" }
        if c.contains("yabai -m window --resize right:") { return "Resize Right" }
        if c.contains("yabai -m window --resize top:") { return "Resize Up" }
        if c.contains("yabai -m window --resize bottom:") { return "Resize Down" }
        if c.contains("yabai -m window --toggle float") { return "Toggle Float/Tile" }
        if c.contains("yabai -m space --layout bsp"), c.contains("yabai -m space --balance") { return "Tile Layout + Balance" }
        if c.contains("yabai -m space --layout stack") { return "Stack Layout" }
        if c.contains("yabai -m space --balance") { return "Balance Tiles" }
        if c.contains("yabai -m space --rotate") { return "Rotate Layout" }

        if let scriptPath = scriptPath(from: entry.command) {
            return scriptDisplayTitle(from: scriptPath)
        }

        return shortcutExplanation(entry)
    }

    private func scriptPath(from command: String) -> String? {
        guard let firstTokenRaw = command.split(whereSeparator: \.isWhitespace).first else { return nil }
        let firstToken = String(firstTokenRaw).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard firstToken.hasPrefix("/") || firstToken.hasPrefix("~/") || firstToken.hasPrefix("./") else { return nil }

        if firstToken.hasPrefix("./") {
            let baseURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config")
                .appendingPathComponent("skhd", isDirectory: true)
            return URL(fileURLWithPath: firstToken, relativeTo: baseURL)
                .standardizedFileURL
                .path
        }

        return NSString(string: firstToken).expandingTildeInPath
    }

    private func scriptDisplayTitle(from path: String) -> String {
        let base = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let cleaned = base.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        let tokens = cleaned
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !tokens.isEmpty else { return "Script Action" }
        return tokens
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func scriptDescriptionFromHeader(path: String) -> String? {
        if let cached = scriptHeaderDescriptionCache[path] {
            return cached
        }

        let description: String?
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            description = content
                .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .prefix(20)
                .compactMap { rawLine -> String? in
                    let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty || line.hasPrefix("#!") || !line.hasPrefix("#") { return nil }
                    let comment = String(line.dropFirst())
                        .trimmingCharacters(in: CharacterSet(charactersIn: " .:-\t"))
                    guard !comment.isEmpty else { return nil }
                    if comment.hasSuffix(".") || comment.hasSuffix("!") || comment.hasSuffix("?") {
                        return comment
                    }
                    return comment + "."
                }
                .first
        } else {
            description = nil
        }

        scriptHeaderDescriptionCache[path] = description
        return description
    }

    private func scriptFallbackDescription(from path: String) -> String {
        let title = scriptDisplayTitle(from: path)
        return "Uses the \(title.lowercased()) helper."
    }

    private func normalizedShortcutCopy(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func actionMeta(for actionID: TilePilotActionID) -> (
        title: String,
        subtitle: String,
        category: String,
        buttonLabel: String,
        requiredCapabilities: [String],
        requiresLiveState: Bool,
        disableInDegradedMode: Bool
    ) {
        switch actionID {
        case .balanceSpace:
            return ("Balance Tiles", "Evenly space tiles on the current desktop", "Layouts", "Balance", ["yabai-binary", "yabai-daemon", "yabai-query"], true, true)
        case .layoutBSPAndBalance:
            return ("Tile Layout + Balance", "Use split tiling layout, then rebalance tiles", "Layouts", "Set Tile Layout", ["yabai-binary", "yabai-daemon", "yabai-query"], true, true)
        case .layoutStack:
            return ("Stack Layout", "Show windows in a stack layout on the current desktop", "Layouts", "Set Stack Layout", ["yabai-binary", "yabai-daemon", "yabai-query"], true, true)
        case .toggleFloat:
            return ("Toggle Float/Tile", "Switch the focused window between floating and tiled", "Window", "Toggle", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusWest:
            return ("Focus Left", "Move focus to the window on the left", "Focus", "Focus Left", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusEast:
            return ("Focus Right", "Move focus to the window on the right", "Focus", "Focus Right", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusNorth:
            return ("Focus Up", "Move focus to the window above", "Focus", "Focus Up", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .focusSouth:
            return ("Focus Down", "Move focus to the window below", "Focus", "Focus Down", ["yabai-binary", "yabai-daemon", "yabai-query"], true, false)
        case .browserReliefPlaceholder:
            return ("Browser Relief", "Planned helper workflow", "Layouts", "Run", ["yabai-binary"], false, true)
        }
    }

    private func userFacingDisabledReason(forCapabilityKey key: String, capability: CapabilityState) -> String {
        switch key {
        case "yabai-binary":
            return "Install yabai first."
        case "yabai-daemon":
            return "Start yabai, then try again."
        case "yabai-query":
            return "TilePilot can’t read yabai right now. Restart yabai and try again."
        default:
            return capability.message
        }
    }

    private func actionFailureMessage(for actionID: TilePilotActionID, commandResult result: CommandResult) -> String {
        let stderr = trimForUI(result.stderr).lowercased()
        let title = actionMeta(for: actionID).title

        if stderr.contains("could not connect") {
            return "\(title) didn’t run because yabai is not responding. Start or restart yabai, then try again."
        }
        if stderr.contains("no such file") || stderr.contains("not found") {
            return "\(title) didn’t run because yabai is not installed."
        }
        if stderr.contains("scripting-addition") {
            return "\(title) needs yabai desktop control (scripting addition). Use Health/Setup to fix scripting addition."
        }
        let trimmed = trimForUI(result.stderr)
        if trimmed.isEmpty {
            return "\(title) didn’t work."
        }
        return "\(title) didn’t work: \(trimmed)"
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
                        pid: $0.pid,
                        app: $0.app,
                        space: $0.space,
                        display: $0.display,
                        frameX: $0.frameX,
                        frameY: $0.frameY,
                        frameW: $0.frameW,
                        frameH: $0.frameH,
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
