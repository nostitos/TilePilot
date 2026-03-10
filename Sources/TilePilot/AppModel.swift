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
    enum RuntimeBurstSource: CaseIterable {
        case liveStateRefresh
        case liveStatePublish
        case unchangedPoll
        case overviewCacheRebuild
        case shortcutsCacheRebuild
        case keepOnTopEnforcement
        case overlayUpdate
    }

    static let shared = AppModel()
    private static let pinnedShortcutsDefaultsKey = "TilePilot.pinnedShortcutKeys"
    private static let pinnedDirectionalGroupsDefaultsKey = "TilePilot.pinnedDirectionalGroupIDs"
    private static let pinnedFeatureControlsDefaultsKey = "TilePilot.pinnedFeatureControlIDs"
    private static let shortcutsCustomOrderDefaultsKey = "TilePilot.shortcutsCustomOrderIDs"
    static let showWindowBadgeOverlayDefaultsKey = "TilePilot.showWindowBadgeOverlay"
    static let showWindowOutlineOverlayDefaultsKey = "TilePilot.showWindowOutlineOverlay"
    static let raiseOnFloatToggleDefaultsKey = "TilePilot.raiseOnFloatToggle"
    static let appForegroundPolicyByNameDefaultsKey = "TilePilot.appForegroundPolicyByName"
    static let performancePresetDefaultsKey = "TilePilot.performancePreset"
    static let performanceForegroundPollingSecondsDefaultsKey = "TilePilot.performanceForegroundPollingSeconds"
    static let performanceBackgroundPollingSecondsDefaultsKey = "TilePilot.performanceBackgroundPollingSeconds"
    static let performanceKeepOnTopSecondsDefaultsKey = "TilePilot.performanceKeepOnTopSeconds"
    static let performanceMiniMapHoverTitlesEnabledDefaultsKey = "TilePilot.performanceMiniMapHoverTitlesEnabled"
    static let performanceFastLiveRefreshEnabledDefaultsKey = "TilePilot.performanceFastLiveRefreshEnabled"
    static let performanceKeepOnTopEnforcementEnabledDefaultsKey = "TilePilot.performanceKeepOnTopEnforcementEnabled"
    static let releaseDefaultsAppliedVersionDefaultsKey = "TilePilot.releaseDefaultsAppliedVersion"
    static let releaseDefaultsSeenVersionDefaultsKey = "TilePilot.releaseDefaultsSeenVersion"
    static let releaseDefaultsInitializedDefaultsKey = "TilePilot.releaseDefaultsInitialized"

    private static func loadAppForegroundPolicyByName() -> [String: AppForegroundPolicy] {
        guard let raw = UserDefaults.standard.dictionary(forKey: AppModel.appForegroundPolicyByNameDefaultsKey) as? [String: String] else {
            return [:]
        }
        var mapped: [String: AppForegroundPolicy] = [:]
        for (appKey, rawPolicy) in raw {
            guard let policy = AppForegroundPolicy(rawValue: rawPolicy) else { continue }
            mapped[appKey] = policy
        }
        return mapped
    }

    @Published private(set) var doctorSnapshot: DoctorSnapshot?
    @Published private(set) var bootstrapSnapshot: SetupBootstrapSnapshot?
    @Published private(set) var liveStateSnapshot: LiveStateSnapshot?
    @Published var windowBadges: [WindowBadgeState] = []
    @Published var hoveredWindowIDForBadges: Int?
    @Published private(set) var requestedTilePilotTab: TilePilotTab?
    @Published private(set) var requestedSystemPanelSection: SystemPanelSection?
    @Published private(set) var shortcutEntries: [ShortcutEntry] = []
    @Published var pinnedShortcutKeys: [String] = UserDefaults.standard.stringArray(forKey: AppModel.pinnedShortcutsDefaultsKey) ?? []
    @Published var pinnedDirectionalGroupIDs: [String] = UserDefaults.standard.stringArray(forKey: AppModel.pinnedDirectionalGroupsDefaultsKey) ?? []
    @Published var pinnedFeatureControlIDs: [String] = UserDefaults.standard.stringArray(forKey: AppModel.pinnedFeatureControlsDefaultsKey) ?? []
    @Published var shortcutsCustomOrderIDs: [String] = UserDefaults.standard.stringArray(forKey: AppModel.shortcutsCustomOrderDefaultsKey) ?? []
    @Published var selectedShortcutStableKey: String?
    @Published private(set) var requestedFileEditorTarget: EditorTarget?
    @Published var releaseDefaultsStatus: ReleaseDefaultsStatus = .neverApplied(currentVersion: ReleaseDefaultsService.currentProfileVersion)
    @Published var managedConfigDraft: String = ""
    @Published var editableFiles: [EditableConfigFile] = []
    @Published var selectedEditableFilePath: String?
    @Published var selectedEditableFileBackups: [ConfigBackupInfo] = []
    @Published var selectedEditableFileExists = false
    @Published var selectedEditableFileKind: EditableFileKind = .other
    @Published var editableFileDraft: String = ""
    @Published var editableFileOriginal: String = ""
    @Published var editableFileJumpTargetLine: Int?
    @Published var isRefreshingEditableFiles = false
    @Published var isLoadingEditableFile = false
    @Published var isSavingEditableFile = false
    @Published var isRestoringEditableFile = false
    @Published var filesLastErrorMessage: String?
    @Published var filesLastActionMessage: String?
    @Published var commandLogs: [CommandLogEntry] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isRefreshingBootstrap = false
    @Published private(set) var isRefreshingLiveState = false
    @Published private(set) var isRefreshingShortcuts = false
    @Published var isRefreshingConfig = false
    @Published var isSavingConfig = false
    @Published var isRestoringConfig = false
    @Published var activeActionID: TilePilotActionID?
    @Published var isLaunchingSetupInstaller = false
    @Published var isLaunchingScriptingAdditionFix = false
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
    @Published var configFilePath: String?
    @Published var configBackups: [ConfigBackupInfo] = []
    @Published var configFileExists = false
    @Published var configHasManagedSection = false
    @Published var configDiffPreviewText: String = "No changes."
    @Published var yabaiConfigFilePath: String?
    @Published var yabaiConfigBackups: [ConfigBackupInfo] = []
    @Published var yabaiConfigFileExists = false
    @Published var yabaiConfigHasManagedSection = false
    @Published var yabaiConfigDiffPreviewText: String = "No changes."
    @Published var isRefreshingYabaiConfig = false
    @Published var isSavingYabaiConfig = false
    @Published var isRestoringYabaiConfig = false
    @Published var windowBehaviorPolicyDraft = ManagedWindowBehaviorPolicy.default
    @Published var windowBehaviorAutosaveActionMessage: String?
    @Published var windowBehaviorAutosaveErrorMessage: String?
    @Published var stagedNeverTileApps: [String] = []
    @Published var stagedAlwaysTileApps: [String] = []
    @Published var isApplyingStagedAppRules = false
    @Published var raiseOnFloatToggleEnabled: Bool = true
    @Published var appForegroundPolicyByName: [String: AppForegroundPolicy] = AppModel.loadAppForegroundPolicyByName()
    @Published var performancePreset: PerformancePreset = {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: AppModel.performancePresetDefaultsKey),
              let preset = PerformancePreset(rawValue: raw) else {
            return .balanced
        }
        return preset
    }()
    @Published var performanceForegroundPollingSeconds: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.performanceForegroundPollingSecondsDefaultsKey) == nil {
            return PerformanceSettings.balanced.foregroundPollingSeconds
        }
        return defaults.double(forKey: AppModel.performanceForegroundPollingSecondsDefaultsKey)
    }()
    @Published var performanceBackgroundPollingSeconds: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.performanceBackgroundPollingSecondsDefaultsKey) == nil {
            return PerformanceSettings.balanced.backgroundPollingSeconds
        }
        return defaults.double(forKey: AppModel.performanceBackgroundPollingSecondsDefaultsKey)
    }()
    @Published var performanceKeepOnTopEnforcementSeconds: Double = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.performanceKeepOnTopSecondsDefaultsKey) == nil {
            return PerformanceSettings.balanced.keepOnTopEnforcementSeconds
        }
        return defaults.double(forKey: AppModel.performanceKeepOnTopSecondsDefaultsKey)
    }()
    @Published var miniMapHoverTitlesEnabled: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.performanceMiniMapHoverTitlesEnabledDefaultsKey) == nil {
            return PerformanceSettings.balanced.miniMapHoverTitlesEnabled
        }
        return defaults.bool(forKey: AppModel.performanceMiniMapHoverTitlesEnabledDefaultsKey)
    }()
    @Published var performanceFastLiveRefreshEnabled: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.performanceFastLiveRefreshEnabledDefaultsKey) == nil {
            return PerformanceSettings.balanced.fastLiveRefreshEnabled
        }
        return defaults.bool(forKey: AppModel.performanceFastLiveRefreshEnabledDefaultsKey)
    }()
    @Published var keepOnTopEnforcementEnabled: Bool = {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: AppModel.performanceKeepOnTopEnforcementEnabledDefaultsKey) == nil {
            return PerformanceSettings.balanced.keepOnTopEnforcementEnabled
        }
        return defaults.bool(forKey: AppModel.performanceKeepOnTopEnforcementEnabledDefaultsKey)
    }()
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

    let doctorService = DoctorService()
    let bootstrapService = BootstrapService()
    private let yabaiStateService = YabaiStateService()
    private let skhdShortcutService = SkhdShortcutService()
    let configService = ConfigService()
    let yabaiRulesConfigService = YabaiRulesConfigService()
    let configFilesService = ConfigFilesService()
    let releaseDefaultsService = ReleaseDefaultsService()
    private let keepOnTopCoordinator = KeepOnTopCoordinator()
    private(set) var overviewDisplayPreviews: [OverviewDisplayPreview] = []
    private(set) var overviewDisplaySections: [OverviewDisplaySection] = []
    private(set) var cachedUnifiedControlRows: [UnifiedControlRow] = []
    private(set) var cachedFeatureControlRows: [FeatureControlRow] = []
    private(set) var cachedFeatureControlRowByShortcutStableKey: [String: FeatureControlRow] = [:]
    private(set) var cachedFeatureControlRowByFeatureID: [String: FeatureControlRow] = [:]
    private(set) var cachedShortcutTitleByStableKey: [String: String] = [:]
    private(set) var cachedShortcutSecondaryByStableKey: [String: String?] = [:]
    private(set) var cachedShortcutComboWordsByStableKey: [String: String] = [:]
    private(set) var cachedShortcutComboSymbolsSpacedByStableKey: [String: String] = [:]
    private(set) var cachedFlatShortcutsOrderRankByID: [String: Int] = [:]
    private(set) var cachedPinnedFeatureControlRows: [FeatureControlRow] = []
    private(set) var cachedPinnedShortcutEntries: [ShortcutEntry] = []
    private(set) var cachedPinnedDirectionalGroupBindings: [(group: DirectionalShortcutGroup, bindings: [DirectionalShortcutBinding])] = []
    private(set) var cachedPinnedShortcutContextItems: [PinnedShortcutContextItem] = []
    @Published var runtimeDiagnostics = RuntimeDiagnostics()
    private var autoRefreshTask: Task<Void, Never>?
    private var statePollingTask: Task<Void, Never>?
    private var lastLiveStateContentSignature: String?
    var latestLiveStateSnapshot: LiveStateSnapshot?
    private var overviewCachesDirty = true
    private var shortcutPresentationCachesDirty = true
    private var runtimeBurstSamples: [RuntimeBurstSource: [Date]] = [:]
    var runtimeDiagnosticsStorage = RuntimeDiagnostics()
    var lastRuntimeDiagnosticsPublishAt: Date?
    private var degradedModeActive = false
    private var consecutiveMismatchSamples = 0
    private var consecutiveHealthySamples = 0
    private let degradedEnterThreshold = 3
    private let degradedExitThreshold = 5
    var originalManagedConfigSection: String = ""
    var loadedFullConfigContent: String = ""
    var originalWindowBehaviorPolicy = ManagedWindowBehaviorPolicy.default
    var originalYabaiManagedConfigSection: String = ""
    var scriptHeaderDescriptionCache: [String: String?] = [:]
    var externalYabaiAppBehaviorByName: [String: AppTilingBehavior] = [:]
    private let initialSetupLandingShownDefaultsKey = "TilePilot.initialSetupLandingShown"
    private let firstLaunchGreetingShownDefaultsKey = "TilePilot.firstLaunchGreetingShown"
    let managedFeatureMarkerPrefix = "# TILEPILOT_FEATURE "
    var hasAttemptedReleaseDefaultsInitialization = false
    var windowBehaviorAutoSaveTask: Task<Void, Never>?
    let windowBehaviorAutoSaveDelayNanoseconds: UInt64 = 400_000_000
    var hasInitializedStagedAppRuleLists = false
    var currentVisibleTab: TilePilotTab = .now

    func startIfNeeded() {
        guard autoRefreshTask == nil else { return }
        Task { [weak self] in
            await self?.ensureReleaseDefaultsInitializedIfNeeded()
        }
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
        windowBehaviorAutoSaveTask?.cancel()
        windowBehaviorAutoSaveTask = nil
    }

    func refreshDoctor() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await doctorService.runDoctor()
        doctorSnapshot = result.snapshot
        prependCommandLogs(result.commandLogs)
        // Pinned menus depend on feature disabled/enabled state from doctorSnapshot
        // even when the Shortcuts tab has never been opened.
        rebuildShortcutPresentationCaches()
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

    var shouldShowFirstLaunchGreeting: Bool {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: firstLaunchGreetingShownDefaultsKey) else { return false }
        guard let snapshot = doctorSnapshot else { return false }

        let setupNeeded = snapshot.capabilities.contains { capability in
            switch capability.key {
            case "yabai-binary", "skhd-binary", "yabai-daemon", "skhd-daemon":
                return capability.status != .available
            default:
                return false
            }
        }

        let accessibilityNeedsAttention = snapshot.capabilities.contains { capability in
            capability.key == "accessibility" && capability.status != .available
        }

        return setupNeeded || accessibilityNeedsAttention
    }

    func dismissFirstLaunchGreeting() {
        UserDefaults.standard.set(true, forKey: firstLaunchGreetingShownDefaultsKey)
    }

    func publishLiveStateSnapshotIfNeeded(_ snapshot: LiveStateSnapshot? = nil, force: Bool = false) {
        let target = snapshot ?? latestLiveStateSnapshot
        guard force || hasVisibleTilePilotWindow else { return }
        guard liveStateSnapshot != target else { return }
        liveStateSnapshot = target
    }

    func refreshLiveState() async {
        guard !isRefreshingLiveState else { return }
        isRefreshingLiveState = true
        defer { isRefreshingLiveState = false }

        recordRuntimeBurst(.liveStateRefresh)
        mutateRuntimeDiagnostics { $0.liveStateRefreshCount += 1 }
        let previousSnapshot = latestLiveStateSnapshot ?? liveStateSnapshot
        let poll = await yabaiStateService.pollLiveState()
        applyDegradedModeCounters(yabaiWindowTotal: poll.yabaiWindowTotal, fallbackWindowTotal: poll.fallbackWindowTotal)

        let snapshot = makeLiveStateSnapshot(from: poll)
        latestLiveStateSnapshot = snapshot
        let contentSignature = liveStateContentSignature(for: snapshot)
        if lastLiveStateContentSignature == contentSignature {
            recordRuntimeBurst(.unchangedPoll)
            mutateRuntimeDiagnostics { $0.liveStateUnchangedPollCount += 1 }
            updateRuntimeDiagnosticsMode(for: snapshot)
            await enforceKeepOnTopPoliciesIfNeeded(for: snapshot)
            return
        }
        lastLiveStateContentSignature = contentSignature
        recordRuntimeBurst(.liveStatePublish)
        mutateRuntimeDiagnostics { $0.liveStatePublishedCount += 1 }
        updateOverviewCachesForCurrentVisibility(with: snapshot)
        publishLiveStateSnapshotIfNeeded(snapshot)
        refreshWindowBadgesIfNeeded()
        updateRuntimeDiagnosticsMode(for: snapshot)
        await applyForegroundPolicyTransitions(previous: previousSnapshot, current: snapshot)
        await enforceKeepOnTopPoliciesIfNeeded(for: snapshot)
    }

    func refreshShortcuts() async {
        guard !isRefreshingShortcuts else { return }
        isRefreshingShortcuts = true
        defer { isRefreshingShortcuts = false }

        let result = await skhdShortcutService.loadShortcuts()
        let visibleEntries = result.entries.filter { !isDeprecatedHiddenShortcut($0) }
        shortcutEntries = visibleEntries.sorted {
            if $0.category != $1.category { return $0.category < $1.category }
            if $0.combo != $1.combo { return $0.combo < $1.combo }
            return $0.sourceLine < $1.sourceLine
        }
        prunePinnedShortcutKeysToLoadedEntries()
        scriptHeaderDescriptionCache.removeAll()
        shortcutFilePath = result.filePath
        shortcutParseIssues = result.issues
        migrateLegacyPinnedShortcutsToFeaturePins()
        reconcileShortcutsCustomOrderIDsToCurrentItems()
        // Menu-bar and badge context menus depend on these rows even before the
        // Shortcuts tab is opened, so keep the model cache warm on load.
        rebuildShortcutPresentationCaches()
        await refreshEditableFiles()
    }

    func toggleWindowBadgeOverlay() {
        setWindowBadgeOverlayEnabled(!showWindowBadgeOverlay)
        lastActionMessage = showWindowBadgeOverlay ? "Window badges enabled." : "Window badges disabled."
        lastErrorMessage = nil
    }

    func toggleWindowOutlineOverlay() {
        setWindowOutlineOverlayEnabled(!showWindowOutlineOverlay)
        lastActionMessage = showWindowOutlineOverlay ? "Window outline overlay enabled." : "Window outline overlay disabled."
        lastErrorMessage = nil
    }

    func shortcutExplanation(_ entry: ShortcutEntry) -> String {
        shortcutExplanation(combo: entry.combo, command: entry.command, category: entry.category)
    }

    func shortcutTitle(_ entry: ShortcutEntry) -> String {
        cachedShortcutTitleByStableKey[entry.stableKey] ?? shortcutTitle(for: entry)
    }

    func shortcutSecondaryText(_ entry: ShortcutEntry) -> String? {
        if let cached = cachedShortcutSecondaryByStableKey[entry.stableKey] {
            return cached
        }
        let title = shortcutTitle(entry)
        let explanation = shortcutExplanation(entry)
        if normalizedShortcutCopy(title) == normalizedShortcutCopy(explanation) {
            return nil
        }
        return explanation
    }

    func actionButtonLabel(for actionID: TilePilotActionID) -> String {
        TilePilotActionCatalog.meta(for: actionID).buttonLabel
    }

    func updateManagedConfigDraft(_ newValue: String) {
        managedConfigDraft = newValue
        recomputeConfigDiffPreview()
    }

    func persistPinnedShortcutKeys() {
        UserDefaults.standard.set(pinnedShortcutKeys, forKey: AppModel.pinnedShortcutsDefaultsKey)
    }

    func persistPinnedDirectionalGroupIDs() {
        UserDefaults.standard.set(pinnedDirectionalGroupIDs, forKey: AppModel.pinnedDirectionalGroupsDefaultsKey)
    }

    func persistPinnedFeatureControlIDs() {
        UserDefaults.standard.set(pinnedFeatureControlIDs, forKey: AppModel.pinnedFeatureControlsDefaultsKey)
    }

    func persistShortcutsCustomOrderIDs() {
        UserDefaults.standard.set(shortcutsCustomOrderIDs, forKey: AppModel.shortcutsCustomOrderDefaultsKey)
    }

    private func migrateLegacyPinnedShortcutsToFeaturePins() {
        guard !pinnedShortcutKeys.isEmpty else { return }

        var remainingLegacy: [String] = []
        var migrated = false
        for key in pinnedShortcutKeys {
            guard let entry = shortcutEntries.first(where: { $0.stableKey == key }) else {
                remainingLegacy.append(key)
                continue
            }
            guard let featureID = featureDefinition(for: entry)?.id else {
                remainingLegacy.append(key)
                continue
            }
            if !pinnedFeatureControlIDs.contains(featureID.rawValue) {
                pinnedFeatureControlIDs.append(featureID.rawValue)
            }
            migrated = true
        }

        pinnedShortcutKeys = Array(NSOrderedSet(array: remainingLegacy)) as? [String] ?? remainingLegacy
        pinnedFeatureControlIDs = Array(NSOrderedSet(array: pinnedFeatureControlIDs)) as? [String] ?? pinnedFeatureControlIDs

        if migrated {
            persistPinnedShortcutKeys()
            persistPinnedFeatureControlIDs()
        }
    }

    private func prunePinnedShortcutKeysToLoadedEntries() {
        guard !pinnedShortcutKeys.isEmpty else { return }
        let knownKeys = Set(shortcutEntries.map(\.stableKey))
        let pruned = pinnedShortcutKeys.filter { knownKeys.contains($0) }
        guard pruned != pinnedShortcutKeys else { return }
        pinnedShortcutKeys = pruned
        persistPinnedShortcutKeys()
    }

    private func isDeprecatedHiddenShortcut(_ entry: ShortcutEntry) -> Bool {
        // Space-relief was an old experimental idea and should no longer appear in TilePilot UI.
        entry.command.lowercased().contains("space-relief.sh")
    }

    func directionalShortcutBinding(for entry: ShortcutEntry) -> DirectionalShortcutBinding? {
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

    var isWindowBehaviorDraftDirty: Bool {
        windowBehaviorPolicyDraft != originalWindowBehaviorPolicy
    }

    var isAppRuleListApplyRequired: Bool {
        let stagedNeverKeys = Set(stagedNeverTileApps.map(normalizedAppRuleKey))
        let stagedAlwaysKeys = Set(stagedAlwaysTileApps.map(normalizedAppRuleKey))
        let savedNeverKeys = Set(windowBehaviorPolicyDraft.neverTileApps.map(normalizedAppRuleKey))
        let savedAlwaysKeys = Set(windowBehaviorPolicyDraft.alwaysTileApps.map(normalizedAppRuleKey))
        return stagedNeverKeys != savedNeverKeys || stagedAlwaysKeys != savedAlwaysKeys
    }

    func addNeverTileApp(_ name: String) {
        addStagedNeverTileApp(name)
    }

    func removeNeverTileApp(_ name: String) {
        removeStagedNeverTileApp(name)
    }

    func addAlwaysTileApp(_ name: String) {
        addStagedAlwaysTileApp(name)
    }

    func removeAlwaysTileApp(_ name: String) {
        removeStagedAlwaysTileApp(name)
    }

    func featureDefinition(forActionID actionID: TilePilotActionID) -> FeatureDefinition? {
        featureDefinitions.first(where: { $0.actionID == actionID })
    }

    enum FloatingBringReason {
        case manualAll
        case manualFlagged
        case autoTransition
        case floatToggle
        case autoEnforce
    }

    private func applyForegroundPolicyTransitions(previous: LiveStateSnapshot?, current: LiveStateSnapshot) async {
        await keepOnTopCoordinator.applyForegroundPolicyTransitions(on: self, previous: previous, current: current)
    }

    private func enforceKeepOnTopPoliciesIfNeeded(for snapshot: LiveStateSnapshot) async {
        guard keepOnTopEnforcementEnabled else { return }
        guard hasActiveKeepOnTopWindows else { return }
        recordRuntimeBurst(.keepOnTopEnforcement)
        mutateRuntimeDiagnostics { $0.keepOnTopEnforcementPassCount += 1 }
        await keepOnTopCoordinator.enforceKeepOnTopPoliciesIfNeeded(on: self, snapshot: snapshot)
    }

    func activeSpaceIndex(in snapshot: LiveStateSnapshot) -> Int? {
        snapshot.windows.first(where: \.focused)?.space
            ?? snapshot.spaces.first(where: \.focused)?.index
            ?? snapshot.spaces.first(where: \.visible)?.index
    }

    func bringFloatingWindowsToFrontCurrentDesktop(
        flaggedOnly: Bool,
        reason: FloatingBringReason,
        bypassCooldown: Bool
    ) async {
        await keepOnTopCoordinator.bringFloatingWindowsToFrontCurrentDesktop(
            on: self,
            flaggedOnly: flaggedOnly,
            reason: reason,
            bypassCooldown: bypassCooldown
        )
    }

    func raiseWindowOnly(
        windowID: Int,
        targetSpace: Int?,
        bypassCooldown: Bool = false,
        allowFocusFallback: Bool = false
    ) async -> Bool {
        await keepOnTopCoordinator.raiseWindowOnly(
            on: self,
            windowID: windowID,
            targetSpace: targetSpace,
            bypassCooldown: bypassCooldown,
            allowFocusFallback: allowFocusFallback
        )
    }

    func bringWindowToFront(windowID: Int) async {
        await keepOnTopCoordinator.bringWindowToFront(on: self, windowID: windowID)
    }

    func matchingActionID(forShortcutIntentKey intentKey: String) -> TilePilotActionID? {
        TilePilotActionID.allCases.first { actionIntentKey(for: $0) == intentKey }
    }

    func actionIntentKey(for actionID: TilePilotActionID) -> String {
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

    func shortcutIntentKey(for entry: ShortcutEntry) -> String {
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

    func unifiedGroup(for entry: ShortcutEntry) -> UnifiedControlGroup {
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

    func unifiedGroup(forActionCategory category: String) -> UnifiedControlGroup {
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
                    frameX: 0,
                    frameY: 0,
                    frameW: 0,
                    frameH: 0,
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
                        frameX: $0.frameX,
                        frameY: $0.frameY,
                        frameW: $0.frameW,
                        frameH: $0.frameH,
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
                        hasAXReference: $0.hasAXReference,
                        canMove: $0.canMove,
                        canResize: $0.canResize,
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

    private func rebuildOverviewCaches(from snapshot: LiveStateSnapshot) {
        overviewDisplayPreviews = buildOverviewPreviews(from: snapshot)
        overviewDisplaySections = OverviewSectionsBuilder.build(snapshot: snapshot, isExcluded: isOverviewExcludedWindow)
        overviewCachesDirty = false
        recordRuntimeBurst(.overviewCacheRebuild)
        mutateRuntimeDiagnostics { $0.overviewCacheRebuildCount += 1 }
    }

    func rebuildShortcutPresentationCaches() {
        cachedUnifiedControlRows = buildUnifiedControlRows()
        cachedFeatureControlRows = buildFeatureControlRows(from: cachedUnifiedControlRows)
        cachedFeatureControlRowByShortcutStableKey = Dictionary(
            cachedFeatureControlRows.compactMap { row in
                row.shortcutEntry.map { ($0.stableKey, row) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        cachedFeatureControlRowByFeatureID = Dictionary(
            cachedFeatureControlRows.compactMap { row in
                row.featureID.map { ($0.rawValue, row) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        cachedShortcutTitleByStableKey = Dictionary(
            shortcutEntries.map { ($0.stableKey, shortcutTitle(for: $0)) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedShortcutSecondaryByStableKey = Dictionary(
            shortcutEntries.map { entry in
                let title = cachedShortcutTitleByStableKey[entry.stableKey] ?? shortcutTitle(for: entry)
                let explanation = shortcutExplanation(entry)
                let secondary = normalizedShortcutCopy(title) == normalizedShortcutCopy(explanation) ? nil : explanation
                return (entry.stableKey, secondary)
            },
            uniquingKeysWith: { first, _ in first }
        )
        cachedShortcutComboWordsByStableKey = Dictionary(
            shortcutEntries.map { ($0.stableKey, parseShortcutComboDisplay($0.combo).words) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedShortcutComboSymbolsSpacedByStableKey = Dictionary(
            shortcutEntries.map { ($0.stableKey, parseShortcutComboDisplay($0.combo).symbolsSpaced) },
            uniquingKeysWith: { first, _ in first }
        )
        cachedFlatShortcutsOrderRankByID = buildFlatShortcutsOrderRankByID()
        cachedPinnedFeatureControlRows = buildPinnedFeatureControlRows(orderRank: cachedFlatShortcutsOrderRankByID)
        cachedPinnedShortcutEntries = buildPinnedShortcutEntries(orderRank: cachedFlatShortcutsOrderRankByID)
        cachedPinnedDirectionalGroupBindings = buildPinnedDirectionalGroupBindings(orderRank: cachedFlatShortcutsOrderRankByID)
        cachedPinnedShortcutContextItems = buildPinnedShortcutContextItems(
            orderRank: cachedFlatShortcutsOrderRankByID,
            pinnedFeatureRows: cachedPinnedFeatureControlRows,
            pinnedDirectionalBindings: cachedPinnedDirectionalGroupBindings,
            pinnedEntries: cachedPinnedShortcutEntries
        )
        shortcutPresentationCachesDirty = false
        recordRuntimeBurst(.shortcutsCacheRebuild)
        mutateRuntimeDiagnostics { $0.shortcutsCacheRebuildCount += 1 }
    }

    func ensureOverviewCachesIfNeeded() {
        publishLiveStateSnapshotIfNeeded(force: true)
        guard overviewCachesDirty, let snapshot = latestLiveStateSnapshot ?? liveStateSnapshot else { return }
        guard hasVisibleTilePilotWindow, currentVisibleTab == .now else { return }
        rebuildOverviewCaches(from: snapshot)
    }

    func ensureShortcutPresentationCachesIfNeeded() {
        publishLiveStateSnapshotIfNeeded(force: true)
        guard shortcutPresentationCachesDirty else { return }
        guard hasVisibleTilePilotWindow, currentVisibleTab == .actions else { return }
        rebuildShortcutPresentationCaches()
    }

    func invalidateOverviewCaches() {
        overviewCachesDirty = true
    }

    func invalidateShortcutPresentationCaches() {
        shortcutPresentationCachesDirty = true
    }

    private func updateOverviewCachesForCurrentVisibility(with snapshot: LiveStateSnapshot) {
        if hasVisibleTilePilotWindow && currentVisibleTab == .now {
            rebuildOverviewCaches(from: snapshot)
        } else {
            invalidateOverviewCaches()
        }
    }

    private func refreshWindowBadgesIfNeeded() {
        guard showWindowBadgeOverlay || showWindowOutlineOverlay else {
            refreshWindowBadges()
            return
        }
        guard hasActiveOverlayConsumer else { return }
        refreshWindowBadges()
    }

    var hasActiveOverlayConsumer: Bool {
        hasVisibleTilePilotWindow || currentVisibleTab == .now || hasVisibleWindowBadgePanels
    }

    var hasVisibleWindowBadgePanels = false

    func setHasVisibleWindowBadgePanels(_ value: Bool) {
        guard hasVisibleWindowBadgePanels != value else { return }
        hasVisibleWindowBadgePanels = value
    }

    func recordRuntimeBurst(_ source: RuntimeBurstSource) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-10)
        for key in RuntimeBurstSource.allCases {
            runtimeBurstSamples[key] = (runtimeBurstSamples[key] ?? []).filter { $0 >= cutoff }
        }
        runtimeBurstSamples[source, default: []].append(now)
        mutateRuntimeDiagnostics { diagnostics in
            diagnostics.recentLiveStateRefreshCount = runtimeBurstSamples[.liveStateRefresh]?.count ?? 0
            diagnostics.recentLiveStatePublishedCount = runtimeBurstSamples[.liveStatePublish]?.count ?? 0
            diagnostics.recentLiveStateUnchangedPollCount = runtimeBurstSamples[.unchangedPoll]?.count ?? 0
            diagnostics.recentOverviewCacheRebuildCount = runtimeBurstSamples[.overviewCacheRebuild]?.count ?? 0
            diagnostics.recentShortcutsCacheRebuildCount = runtimeBurstSamples[.shortcutsCacheRebuild]?.count ?? 0
            diagnostics.recentKeepOnTopEnforcementPassCount = runtimeBurstSamples[.keepOnTopEnforcement]?.count ?? 0
            diagnostics.recentOverlayPanelUpdateCount = runtimeBurstSamples[.overlayUpdate]?.count ?? 0
            diagnostics.dominantBurstSource = dominantBurstSourceTitle()
        }
    }

    private func dominantBurstSourceTitle() -> String {
        let liveStateCount = (runtimeBurstSamples[.liveStateRefresh]?.count ?? 0)
            + (runtimeBurstSamples[.liveStatePublish]?.count ?? 0)
            + (runtimeBurstSamples[.unchangedPoll]?.count ?? 0)
        let overlayCount = runtimeBurstSamples[.overlayUpdate]?.count ?? 0
        let keepOnTopCount = runtimeBurstSamples[.keepOnTopEnforcement]?.count ?? 0
        let uiCount = (runtimeBurstSamples[.overviewCacheRebuild]?.count ?? 0)
            + (runtimeBurstSamples[.shortcutsCacheRebuild]?.count ?? 0)
        let entries = [
            ("Live-state polling", liveStateCount),
            ("Overlay updates", overlayCount),
            ("Keep-on-top enforcement", keepOnTopCount),
            ("UI recomposition", uiCount),
        ].filter { $0.1 > 0 }
        guard let maxValue = entries.map(\.1).max() else { return "Idle" }
        let leaders = entries.filter { $0.1 == maxValue }
        if leaders.count == 1 {
            return leaders[0].0
        }
        return "Mixed"
    }

    private func liveStateContentSignature(for snapshot: LiveStateSnapshot) -> String {
        let displays = snapshot.displays.map {
            "\($0.id)|\($0.name)|\($0.frameX)|\($0.frameY)|\($0.frameW)|\($0.frameH)|\($0.focused)|\($0.windowCount)|\($0.source.rawValue)"
        }.joined(separator: "||")
        let spaces = snapshot.spaces.map {
            "\($0.index)|\($0.label ?? "")|\($0.displayId)|\($0.focused)|\($0.visible)|\($0.layout ?? "")|\($0.windowCount)|\($0.source.rawValue)"
        }.joined(separator: "||")
        let windows = snapshot.windows.map {
            "\($0.id)|\($0.pid)|\($0.app)|\($0.space)|\($0.display)|\($0.frameX)|\($0.frameY)|\($0.frameW)|\($0.frameH)|\($0.floating)|\($0.hasAXReference)|\($0.canMove)|\($0.canResize)|\($0.title)|\($0.focused)|\($0.isVisible)|\($0.isMinimized)|\($0.isHidden)|\($0.source.rawValue)"
        }.joined(separator: "||")
        let fallbackDisplays = snapshot.fallbackDisplays.map {
            "\($0.id)|\($0.name)|\($0.windowCount)|\($0.source.rawValue)"
        }.joined(separator: "||")
        return [
            snapshot.source.rawValue,
            snapshot.degraded ? "1" : "0",
            snapshot.degradedReason ?? "",
            String(snapshot.yabaiWindowTotal ?? -1),
            String(snapshot.fallbackWindowTotal ?? -1),
            String(snapshot.consecutiveMismatchSamples),
            String(snapshot.consecutiveHealthySamples),
            snapshot.lastErrorMessage ?? "",
            displays,
            spaces,
            windows,
            fallbackDisplays,
        ].joined(separator: "###")
    }

    func currentKeepOnTopEnforcementIntervalSeconds() -> Double {
        guard runtimeActivityMode.includesKeepOnTopWork else { return 0 }
        var interval = performanceKeepOnTopEnforcementSeconds
        if performanceFastLiveRefreshEnabled {
            interval = min(interval, 0.8)
        }
        return interval
    }
}
