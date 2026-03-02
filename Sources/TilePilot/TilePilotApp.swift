import AppKit
import SwiftUI

enum TilePilotTab: Hashable {
    case now
    case windowBehavior
    case actions
    case shortcuts
    case system
    // legacy route-only cases (mapped to .system)
    case files
    case config
    case health
    case setup
    case logs
}

@main
struct TilePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        Settings {
            SettingsPlaceholderView()
                .environmentObject(model)
        }
    }
}

struct TilePilotRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: TilePilotTab = .now
    @State private var hasAppliedInitialTabSelection = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NowDashboardView()
                .tabItem { Label("Overview", systemImage: "rectangle.3.group") }
                .tag(TilePilotTab.now)

            WindowBehaviorDashboardView()
                .tabItem { Label("Window Behavior", systemImage: "hand.raised.square") }
                .tag(TilePilotTab.windowBehavior)

            UnifiedControlsDashboardView()
                .tabItem { Label("Actions & Shortcuts", systemImage: "square.grid.2x2") }
                .tag(TilePilotTab.actions)

            FilesDashboardView()
                .tabItem { Label("Config Files", systemImage: "doc.text") }
                .tag(TilePilotTab.files)

            SystemDashboardView()
                .tabItem { Label("System", systemImage: "gearshape.2") }
                .tag(TilePilotTab.system)
        }
        .onChange(of: model.requestedTilePilotTab) { newValue in
            if let newValue {
                switch newValue {
                case .actions, .shortcuts:
                    selectedTab = .actions
                case .files:
                    selectedTab = .files
                case .config, .health, .setup, .logs:
                    selectedTab = .system
                default:
                    selectedTab = newValue
                }
                _ = model.consumeRequestedTilePilotTab()
            }
        }
        .task {
            if !hasAppliedInitialTabSelection {
                selectedTab = model.consumeShouldStartOnSetupTab() ? .system : .now
                hasAppliedInitialTabSelection = true
            }
            model.startIfNeeded()
            if model.doctorSnapshot == nil {
                await model.refreshDoctor()
            }
        }
    }
}

struct UnifiedControlsDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ShortcutsDashboardView()
    }
}

struct SystemDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdvancedConfig = false
    @State private var showAdvancedDiagnostics = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    essentialsCard
                    advancedPanelsCard
                }
                .padding()
            }
            .navigationTitle("TilePilot")
            .task {
                if model.bootstrapSnapshot == nil {
                    await model.refreshBootstrapSetup()
                }
                if model.doctorSnapshot == nil {
                    await model.refreshDoctor()
                }
                applyRequestedSectionIfNeeded()
            }
            .onChange(of: model.requestedSystemPanelSection) { _ in
                applyRequestedSectionIfNeeded()
            }
        }
    }

    private var summaryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("System Overview", systemImage: "gearshape.2")
                    .font(.headline)

                Text(model.systemSummaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(model.systemPrimaryActions, id: \.self) { action in
                        Button(action.label) {
                            model.performSystemCheckAction(action)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if model.systemPrimaryActions.isEmpty {
                        Text("No immediate fixes needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Recheck") {
                        model.performSystemCheckAction(.recheck)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if let error = model.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                if let message = model.lastActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var essentialsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.systemCheckRows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.status.symbolName)
                            .foregroundStyle(color(for: row.status))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                            Text(row.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(row.actions, id: \.self) { action in
                                    Button(action.label) {
                                        model.performSystemCheckAction(action)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Essentials", systemImage: "checklist")
        }
    }

    private var advancedPanelsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("Advanced: Managed skhd Section (Safe Editor)", isExpanded: $showAdvancedConfig) {
                    ConfigDashboardView(showNavigationContainer: false)
                        .frame(minHeight: 380)
                        .padding(.top, 6)
                }

                DisclosureGroup("Advanced: Diagnostics", isExpanded: $showAdvancedDiagnostics) {
                    CommandLogView(showNavigationContainer: false)
                        .frame(minHeight: 280)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Advanced", systemImage: "slider.horizontal.3")
        }
    }

    private func color(for status: SystemCheckStatus) -> Color {
        switch status {
        case .good: return .green
        case .notice: return .yellow
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func applyRequestedSectionIfNeeded() {
        guard let section = model.consumeRequestedSystemPanelSection() else { return }
        switch section {
        case .essentials:
            break
        case .files:
            model.requestOpenTilePilotTab(.files)
        case .managedConfig:
            showAdvancedConfig = true
        case .diagnostics:
            showAdvancedDiagnostics = true
        }
    }
}

struct NowDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedWindowID: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.shouldShowWindowBehaviorRecommendation {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Windows moving around too much?")
                                    .font(.headline)
                                Text("Stabilize your Mac by floating new windows by default and disabling hover focus.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("Enable Manual Tiling Mode") { model.enableManualTilingMode() }
                                    Button("Disable Hover Focus") { model.disableHoverFocus() }
                                    Button("Open Window Behavior") {
                                        model.openWindowBehaviorSettings()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Recommended", systemImage: "sparkles")
                        }
                    }

                    if let snapshot = model.liveStateSnapshot {
                        if snapshot.degraded, let reason = snapshot.degradedReason {
                            degradedBanner(reason: reason)
                        }

                        if snapshot.source == .yabai && !snapshot.degraded {
                            yabaiMapCard(snapshot)
                        } else {
                            fallbackMapCard(snapshot)
                        }
                    } else {
                        EmptyStateView(
                            title: "Loading windows",
                            systemImage: "rectangle.3.group",
                            message: "Loading your windows and desktops. If `yabai` is unavailable, the app falls back to a simpler display view."
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("TilePilot")
            .task {
                await model.refreshLiveState()
            }
        }
    }

    private func degradedBanner(reason: String) -> some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Degraded Mode")
                        .font(.headline)
                    Text(reason)
                        .font(.subheadline)
                    Text("Workspace-precise mapping may be inaccurate. Showing monitor-level fallback counts when needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let liveStateHelp = liveStateHelp(for: reason) {
                        Text(liveStateHelp.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(liveStateHelp.actions, id: \.label) { action in
                                Button(action.label, action: action.handler)
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Degraded", systemImage: "minus.circle")
        }
    }

    private func yabaiMapCard(_ snapshot: LiveStateSnapshot) -> some View {
        let spacesByDisplay = Dictionary(grouping: snapshot.spaces, by: \.displayId)
        let sortedDisplays = snapshot.displays.sorted { lhs, rhs in
            if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
            return lhs.id < rhs.id
        }
        let allWindows = snapshot.windows
        let visibleWindows = snapshot.windows.filter { window in
            window.isVisible && !window.isMinimized && !window.isHidden
        }
        let windowsBySpaceAll = Dictionary(grouping: allWindows, by: \.space)
        let visibleWindowCountByDisplay = Dictionary(grouping: visibleWindows, by: \.display).mapValues(\.count)
        let totalWindowCountByDisplay = Dictionary(grouping: allWindows, by: \.display).mapValues(\.count)
        let visibleWindowCountBySpace = Dictionary(grouping: visibleWindows, by: \.space).mapValues(\.count)
        let totalWindowCountBySpace = Dictionary(grouping: allWindows, by: \.space).mapValues(\.count)
        let runtimeEnabled = model.canRunYabaiRuntimeCommands
        let runtimeDisabledReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if snapshot.displays.isEmpty {
                    Text("No displays returned by yabai.")
                        .foregroundStyle(.secondary)
                } else {
                    if !runtimeEnabled {
                        Text("Window controls unavailable: \(runtimeDisabledReason)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(sortedDisplays) { display in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(display.name, systemImage: display.focused ? "display.and.arrow.down" : "display")
                                    .font(.headline)
                                Spacer()
                                Text("Visible: \(visibleWindowCountByDisplay[display.id] ?? 0) · Total: \(totalWindowCountByDisplay[display.id] ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            let displaySpaces = (spacesByDisplay[display.id] ?? []).sorted { lhs, rhs in
                                if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                                if lhs.visible != rhs.visible { return lhs.visible && !rhs.visible }
                                return lhs.index < rhs.index
                            }
                            if displaySpaces.isEmpty {
                                Text("No desktops returned for this display.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(displaySpaces) { space in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(spaceTitle(space))
                                                .font(.subheadline.weight(.semibold))
                                            Spacer()
                                            Text("Visible: \(visibleWindowCountBySpace[space.index] ?? 0) · Total: \(totalWindowCountBySpace[space.index] ?? 0)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        let visibleCount = visibleWindowCountBySpace[space.index] ?? 0
                                        let totalCount = totalWindowCountBySpace[space.index] ?? 0
                                        let spaceWindows = (windowsBySpaceAll[space.index] ?? []).sorted { lhs, rhs in
                                            if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                                            let lhsVisible = lhs.isVisible && !lhs.isMinimized && !lhs.isHidden
                                            let rhsVisible = rhs.isVisible && !rhs.isMinimized && !rhs.isHidden
                                            if lhsVisible != rhsVisible { return lhsVisible && !rhsVisible }
                                            return lhs.id < rhs.id
                                        }

                                        if totalCount == 0 {
                                            Text("No windows on this desktop.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            if visibleCount == 0 {
                                                Text("No visible windows on this desktop (Total: \(totalCount)).")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            ForEach(spaceWindows) { window in
                                                windowControlRow(
                                                    window: window,
                                                    runtimeEnabled: runtimeEnabled,
                                                    runtimeDisabledReason: runtimeDisabledReason
                                                )
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Displays and Desktops", systemImage: "rectangle.grid.3x2")
        }
    }

    private func fallbackMapCard(_ snapshot: LiveStateSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if snapshot.fallbackDisplays.isEmpty {
                    Text("Fallback monitor counts unavailable.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.fallbackDisplays) { display in
                        HStack {
                            Label(display.name, systemImage: "display")
                            Spacer()
                            Text("\(display.windowCount) visible windows")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Desktop/window mapping is hidden in fallback mode to avoid misleading precision.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Displays (fallback view)", systemImage: "display.2")
        }
    }

    private func spaceTitle(_ space: SpaceState) -> String {
        var parts: [String] = ["Desktop \(space.index)"]
        if let label = space.label, !label.isEmpty {
            parts.append("“\(label)”")
        }
        if space.focused { parts.append("• Focused") }
        else if space.visible { parts.append("• Visible") }
        return parts.joined(separator: " ")
    }

    private func windowControlRow(
        window: WindowState,
        runtimeEnabled: Bool,
        runtimeDisabledReason: String
    ) -> some View {
        let defaultBehavior = defaultBehaviorBadge(for: window.app)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            AppNameWithIconView(appName: window.app)
                .font(.caption.weight(.semibold))

            Text(window.title.isEmpty ? "Untitled" : window.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if window.focused {
                statusPill("Focused", color: .blue)
            }
            if window.isMinimized {
                statusPill("Minimized", color: .secondary)
            } else if window.isHidden {
                statusPill("Hidden", color: .secondary)
            } else if !window.isVisible {
                statusPill("Not Visible", color: .secondary)
            }

            Button {
                model.toggleAppDefaultTilingBehavior(for: window.app)
            } label: {
                statusPill(defaultBehavior.text, color: defaultBehavior.color)
            }
            .buttonStyle(.plain)
            .help(defaultBehavior.help + " Click to toggle default behavior for this app.")

            Button {
                model.toggleWindowFloating(windowID: window.id)
            } label: {
                statusPill(window.floating ? "Floating" : "Tiled", color: window.floating ? .orange : .green)
            }
            .buttonStyle(.plain)
            .disabled(!runtimeEnabled)
            .help(runtimeEnabled ? "Toggle floating/tiled state." : runtimeDisabledReason)

            Menu {
                Button("Set Floating") {
                    model.setWindowFloating(windowID: window.id, shouldFloat: true)
                }
                .disabled(window.floating)
                Button("Set Tiled") {
                    model.setWindowFloating(windowID: window.id, shouldFloat: false)
                }
                .disabled(!window.floating)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .disabled(!runtimeEnabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedWindowID = window.id
        }
        .onTapGesture(count: 2) {
            selectedWindowID = window.id
            model.focusWindow(windowID: window.id)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selectedWindowID == window.id ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedWindowID == window.id ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private func defaultBehaviorBadge(for appName: String) -> (text: String, color: Color, help: String) {
        let behavior = model.appTilingBehavior(for: appName)
        let sourceNote = model.appBehaviorSourceNote(for: appName)
        switch behavior {
        case .neverTile:
            let note = sourceNote ?? "App rule says this app should stay floating by default."
            return ("Default Float", .orange, note)
        case .alwaysTile:
            let note = sourceNote ?? "App rule says this app should be auto-tiled by default."
            return ("Default Tiled", .green, note)
        case .useDefault:
            if model.windowBehaviorPolicyDraft.manualTilingModeEnabled {
                return ("Default Float", .orange, "No app-specific rule. Global default is floating because Manual Tiling Mode is enabled.")
            } else {
                return ("Default Tiled", .green, "No app-specific rule. Global default is auto-tiled.")
            }
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private struct InlineAction {
        let label: String
        let handler: () -> Void
    }

    private struct LiveStateHelp {
        let message: String
        let actions: [InlineAction]
    }

    private func liveStateHelp(for message: String) -> LiveStateHelp? {
        let normalized = message.lowercased()

        if normalized.contains("not installed yet") || normalized.contains("no such file or directory") {
            return LiveStateHelp(
                message: "You only need to care if you want live yabai workspace mapping. Install dependencies to enable the full Now view.",
                actions: [
                    .init(label: "Install Dependencies", handler: { model.runSetupInstallerInTerminal() }),
                    .init(label: "Recheck", handler: { Task { await model.refreshLiveState() } }),
                ]
            )
        }

        if normalized.contains("not running") || normalized.contains("message socket") || normalized.contains("could not connect") {
            return LiveStateHelp(
                message: "yabai appears installed but inactive. Start the service or retry after setup.",
                actions: [
                    .init(label: "Start yabai Service", handler: { model.startBrewServiceYabai() }),
                    .init(label: "Restart yabai", handler: { model.restartYabaiBestEffort() }),
                    .init(label: "Recheck", handler: { Task { await model.refreshLiveState() } }),
                ]
            )
        }

        return nil
    }
}

struct WindowBehaviorDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newNeverTileApp: String = ""
    @State private var newAlwaysTileApp: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    defaultBehaviorCard
                    appRulesCard
                    pointerFocusCard
                    backupCard
                    diffCard
                }
                .padding()
            }
            .navigationTitle("TilePilot")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    applyBar
                        .padding(.horizontal)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                }
                .background(.ultraThinMaterial)
            }
            .task { await model.refreshWindowBehaviorConfig() }
        }
    }

    private var defaultBehaviorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Global default", selection: Binding(
                    get: { model.windowBehaviorPolicyDraft.manualTilingModeEnabled },
                    set: { model.updateManualTilingModeDraft($0) }
                )) {
                    Text("Float by default").tag(true)
                    Text("Auto-tile by default").tag(false)
                }
                .pickerStyle(.segmented)

                Text(model.windowBehaviorPolicyDraft.manualTilingModeEnabled
                     ? "New windows float by default. Use 'Always Tile' as exceptions."
                     : "New windows auto-tile by default. Use 'Never Tile' as exceptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label("Quick toggle focused window", systemImage: "keyboard")
                        .font(.caption.weight(.semibold))
                    Text("Ctrl + ~")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    Text("(keep your mouse in place)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Default Window Behavior", systemImage: "square.grid.3x3.topleft.filled")
        }
    }

    private var pointerFocusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("These settings control how focus changes and whether the cursor moves automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Focus On Hover", selection: Binding(
                    get: { model.windowBehaviorPolicyDraft.hoverFocusMode },
                    set: { model.updateHoverFocusModeDraft($0) }
                )) {
                    ForEach(HoverFocusMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if model.windowBehaviorPolicyDraft.hoverFocusMode != .off {
                    Text("Hover focus can interfere with reaching the macOS menu bar.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Cursor Jumps to Focused Window", isOn: Binding(
                        get: { model.windowBehaviorPolicyDraft.mouseFollowsFocusEnabled },
                        set: { model.updateMouseFollowsFocusDraft($0) }
                    ))
                    .toggleStyle(.switch)

                    Text("When enabled, the pointer moves to the focused window (`mouse_follows_focus`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Focus Behavior", systemImage: "cursorarrow.motionlines")
        }
    }

    private var appRulesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved app behaviors are listed here and persist even when those apps are not currently open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                listEditor(
                    title: "Never Tile Apps",
                    items: model.windowBehaviorPolicyDraft.neverTileApps,
                    newValue: $newNeverTileApp,
                    addAction: { model.addNeverTileApp(newNeverTileApp); newNeverTileApp = "" },
                    removeAction: { model.removeNeverTileApp($0) }
                )

                Divider()

                listEditor(
                    title: "Always Tile Apps",
                    items: model.windowBehaviorPolicyDraft.alwaysTileApps,
                    newValue: $newAlwaysTileApp,
                    addAction: { model.addAlwaysTileApp(newAlwaysTileApp); newAlwaysTileApp = "" },
                    removeAction: { model.removeAlwaysTileApp($0) }
                )

                if !model.availableAppNamesFromLiveState.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Apps Behavior")
                            .font(.subheadline.weight(.semibold))
                        Text(model.windowBehaviorPolicyDraft.manualTilingModeEnabled
                             ? "Choose how each app should behave. 'Default' currently means float by default."
                             : "Choose how each app should behave. 'Default' currently means auto-tile by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CurrentAppsBehaviorListView(apps: model.appNamesForBehaviorEditor)
                        Text("Note: Older rules in your `yabairc` outside the TilePilot managed section can also make apps float/tile.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("App Rules", systemImage: "list.bullet.clipboard")
        }
    }

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Apply Changes") { model.saveWindowBehaviorPolicy() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSavingYabaiConfig || model.isRestoringYabaiConfig)
                Button("Revert Draft") { model.resetWindowBehaviorDraft() }
                    .disabled(!model.isWindowBehaviorDraftDirty)
                Spacer()
                if model.isSavingYabaiConfig || model.isRestoringYabaiConfig || model.isRefreshingYabaiConfig {
                    ProgressView().controlSize(.small)
                }
            }

            if let error = model.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let msg = model.lastActionMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var applyCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                applyBar
            }
        } label: {
            Label("Apply / Revert", systemImage: "checkmark.circle")
        }
    }

    private var backupCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if model.yabaiConfigBackups.isEmpty {
                    Text("No yabairc backups yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.yabaiConfigBackups.prefix(8)) { backup in
                        HStack {
                            Text(URL(fileURLWithPath: backup.path).lastPathComponent)
                                .font(.caption)
                            Spacer()
                            Text(backup.createdAt.formatted(date: .numeric, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Restore") { model.restoreYabaiConfigBackup(backup) }
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Backups", systemImage: "clock.arrow.circlepath")
        }
    }

    private var diffCard: some View {
        GroupBox {
            ScrollView {
                Text(model.yabaiConfigDiffPreviewText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120)
        } label: {
            Label("Managed yabairc Diff", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func listEditor(
        title: String,
        items: [String],
        newValue: Binding<String>,
        addAction: @escaping () -> Void,
        removeAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            HStack {
                TextField("App name (e.g. Finder)", text: newValue)
                Button("Add", action: addAction)
                    .disabled(newValue.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if items.isEmpty {
                Text("No apps configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(spacing: 8) {
                        AppNameWithIconView(appName: item)
                        Button("Remove") { removeAction(item) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

struct FlowLikeAppButtons: View {
    let apps: [String]
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(apps.prefix(16), id: \.self) { app in
                Button {
                    onPick(app)
                } label: {
                    AppNameWithIconView(appName: app)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
            }
        }
    }
}

struct CurrentAppsBehaviorListView: View {
    @EnvironmentObject private var model: AppModel
    let apps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(apps.prefix(24), id: \.self) { app in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        AppNameWithIconView(appName: app)
                            .frame(minWidth: 180, idealWidth: 220, maxWidth: 260, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { model.appTilingBehavior(for: app) },
                            set: { model.setAppTilingBehavior($0, for: app) }
                        )) {
                            ForEach(AppTilingBehavior.allCases, id: \.self) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        Spacer(minLength: 0)
                    }
                    if let note = model.appBehaviorSourceNote(for: app) {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct AppNameWithIconView: View {
    let appName: String

    var body: some View {
        HStack(spacing: 8) {
            if let icon = appIcon() {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "app")
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
            Text(appName)
        }
    }

    private func appIcon() -> NSImage? {
        guard let path = NSWorkspace.shared.fullPath(forApplication: appName) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}

struct ActionsDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    actionsHeaderCard

                    if let snapshot = model.liveStateSnapshot, snapshot.degraded {
                        GroupBox {
                            Text("Some layout actions are temporarily unavailable because TilePilot is using a reduced-precision window view. Window and focus actions may still work.")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            Label("Degraded Mode", systemImage: "exclamationmark.triangle")
                        }
                    }

                    actionSection("Layouts")
                    actionSection("Window")
                    actionSection("Focus")
                }
                .padding()
            }
            .navigationTitle("TilePilot")
        }
    }

    private var actionsHeaderCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Quick Actions", systemImage: "cursorarrow.click")
                        .font(.headline)
                    Spacer()
                    if let action = model.activeActionID {
                        Text("Running: \(actionLabel(action))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Click an action to change the current desktop layout or the focused window.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = model.actionsLastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                if let message = model.actionsLastActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Actions", systemImage: "square.grid.2x2")
        }
    }

    private func actionSection(_ category: String) -> some View {
        let cards = model.actionCards.filter { $0.category == category }
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if cards.isEmpty {
                    Text("No actions in this category yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cards) { card in
                        actionCard(card)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(category, systemImage: iconForCategory(category))
        }
    }

    private func actionCard(_ card: TilePilotActionCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.headline)
                    Text(card.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(buttonTitle(for: card)) {
                    model.performTilePilotAction(card.id)
                }
                .disabled(!card.enabled || model.activeActionID != nil)
            }

            if let reason = card.disabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func buttonTitle(for card: TilePilotActionCard) -> String {
        if model.activeActionID == card.id { return "Running..." }
        return model.actionButtonLabel(for: card.id)
    }

    private func actionLabel(_ action: TilePilotActionID) -> String {
        model.actionCards.first(where: { $0.id == action })?.title ?? action.rawValue
    }

    private func iconForCategory(_ category: String) -> String {
        switch category {
        case "Layouts": return "square.split.2x1"
        case "Window": return "macwindow"
        case "Focus": return "scope"
        default: return "square.grid.2x2"
        }
    }
}

struct ShortcutsDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            shortcutsToolbar
                            searchCard

                            if !model.shortcutParseIssues.isEmpty {
                                issuesCard
                            }

                            shortcutsListCard
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .onChange(of: model.selectedShortcutStableKey) { stableKey in
                        guard let stableKey else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(stableKey, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("TilePilot")
            .task {
                if model.shortcutEntries.isEmpty && !model.isRefreshingShortcuts {
                    await model.refreshShortcuts()
                }
            }
        }
    }

    private var filteredRows: [UnifiedControlRow] {
        model.filteredUnifiedControlRows(query: searchText)
    }

    private var showGroupHeaders: Bool {
        groupedRows.count > 1
    }

    private var groupedRows: [(UnifiedControlGroup, [UnifiedControlRow])] {
        let grouped = Dictionary(grouping: filteredRows, by: \.group)
        let orderedGroups = grouped.keys.sorted { lhs, rhs in
            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return orderedGroups.map { group in
            let rows = grouped[group]?.sorted { lhs, rhs in
                if lhs.title != rhs.title { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
                return lhs.id < rhs.id
            } ?? []
            return (group, rows)
        }
    }

    private var shortcutsToolbar: some View {
        HStack(spacing: 8) {
            Button(model.isRefreshingShortcuts ? "Reloading..." : "Reload Shortcuts") {
                Task { await model.refreshShortcuts() }
            }
            .disabled(model.isRefreshingShortcuts)
            .buttonStyle(.bordered)
            .controlSize(.small)

            if model.isRefreshingShortcuts {
                ProgressView()
                    .controlSize(.small)
            }

            Text("\(filteredRows.count) shown")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !model.pinnedShortcutKeys.isEmpty || !model.pinnedDirectionalGroupIDs.isEmpty {
                HStack(spacing: 8) {
                    Label("\(model.pinnedShortcutEntries.count) pinned", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !model.pinnedDirectionalGroupIDs.isEmpty {
                        Label("\(model.pinnedDirectionalGroups.count) groups", systemImage: "square.grid.2x2")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    private var searchCard: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search controls, shortcuts, or categories", text: $searchText)
        }
        .textFieldStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private var issuesCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(model.shortcutParseIssues.count) lines were skipped while loading shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Logs") {
                model.requestOpenSystemSection(.diagnostics)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var shortcutsListCard: some View {
        Group {
            if filteredRows.isEmpty {
                EmptyStateView(
                    title: model.shortcutEntries.isEmpty ? "No controls loaded" : "No matching controls",
                    systemImage: "keyboard",
                    message: model.shortcutEntries.isEmpty
                        ? "Reload after creating `skhdrc`, or check shortcut parse issues."
                        : "Try a broader search query."
                )
                .frame(minHeight: 160)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedRows, id: \.0) { group, rows in
                        VStack(alignment: .leading, spacing: 6) {
                            if showGroupHeaders {
                                Text(group.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                            }

                            let shortcutEntries = rows.compactMap(\.shortcutEntry)
                            let actionOnlyRows = rows.filter { $0.shortcutEntry == nil }

                            if group == .desktops || group == .experimental {
                                desktopShortcutsSection(shortcutEntries)
                                ForEach(actionOnlyRows, id: \.id) { row in
                                    unifiedActionOnlyRow(row)
                                }
                            } else {
                                directionalShortcutsSection(shortcutEntries)
                                ForEach(actionOnlyRows, id: \.id) { row in
                                    unifiedActionOnlyRow(row)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func shortcutRow(_ entry: ShortcutEntry) -> some View {
        let title = model.shortcutTitle(entry)
        let secondaryText = model.shortcutSecondaryText(entry)
        return HStack(alignment: .center, spacing: 8) {
            comboSummaryView(for: entry)
                .frame(minWidth: 190, idealWidth: 240, maxWidth: 300, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if let secondaryText {
                    Text(secondaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let warning = entry.warning {
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    model.toggleShortcutPinned(entry)
                } label: {
                    Image(systemName: model.isShortcutPinned(entry) ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                }
                .help(model.isShortcutPinned(entry) ? "Unpin from quick menu" : "Pin to quick menu")
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .frame(minWidth: 24)

                Button("Test") {
                    model.runShortcut(entry)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 46)

                Button("Edit") {
                    model.openShortcutSource(entry)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 46)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectShortcut(entry)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(model.isShortcutSelected(entry) ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(model.isShortcutSelected(entry) ? Color.accentColor.opacity(0.30) : Color.clear, lineWidth: 1)
        )
        .id(entry.stableKey)
    }

    private func unifiedActionOnlyRow(_ row: UnifiedControlRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "cursorarrow.click.2")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(row.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let actionID = row.actionID {
                let card = model.actionCard(for: actionID)
                Button("Test") {
                    model.performTilePilotAction(actionID)
                }
                .disabled((card?.enabled == false) || model.activeActionID != nil)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 52)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.04))
        )
    }

    @ViewBuilder
    private func comboSummaryView(for entry: ShortcutEntry) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(model.displayShortcutComboWords(entry))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            shortcutSymbolCaps(for: entry, glyphSize: 14, highlighted: true)
        }
    }

    private struct DesktopShortcutFamilySummary: Identifiable {
        enum Kind: String {
            case goToDesktop
            case moveWindowToDesktopAndFollow
        }

        let kind: Kind
        let entries: [(entry: ShortcutEntry, desktop: Int)]
        var id: String { kind.rawValue }
    }

    private struct DirectionalShortcutFamilySummary: Identifiable {
        enum Kind: String, CaseIterable {
            case focusWindow
            case moveWindow
            case resizeWindow
            case swapWindow
        }

        enum Direction: String, CaseIterable {
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
        }

        let kind: Kind
        let entries: [(entry: ShortcutEntry, direction: Direction)]
        var id: String { kind.rawValue }
    }

    @ViewBuilder
    private func desktopShortcutsSection(_ entries: [ShortcutEntry]) -> some View {
        let summaries = desktopShortcutFamilies(from: entries)
        let covered = Set(summaries.flatMap { $0.entries.map { $0.entry.id } })
        let leftovers = entries.filter { !covered.contains($0.id) }

        VStack(alignment: .leading, spacing: 8) {
            ForEach(summaries) { summary in
                desktopShortcutFamilyCard(summary)
            }
            if !leftovers.isEmpty {
                ForEach(leftovers) { entry in
                    shortcutRow(entry)
                }
            }
        }
    }

    @ViewBuilder
    private func directionalShortcutsSection(_ entries: [ShortcutEntry]) -> some View {
        let summaries = directionalShortcutFamilies(from: entries).filter { $0.kind == .moveWindow }
        let covered = Set(summaries.flatMap { $0.entries.map { $0.entry.id } })
        let leftovers = entries.filter { !covered.contains($0.id) }

        VStack(alignment: .leading, spacing: 8) {
            ForEach(summaries) { summary in
                directionalShortcutFamilyCard(summary)
            }
            if !leftovers.isEmpty {
                ForEach(leftovers) { entry in
                    shortcutRow(entry)
                }
            }
        }
    }

    private func directionalShortcutFamilyCard(_ summary: DirectionalShortcutFamilySummary) -> some View {
        let orderedEntries = summary.entries.sorted { lhs, rhs in
            if lhs.direction.sortRank != rhs.direction.sortRank { return lhs.direction.sortRank < rhs.direction.sortRank }
            return lhs.entry.sourceLine < rhs.entry.sourceLine
        }
        let byDirection = Dictionary(uniqueKeysWithValues: orderedEntries.map { ($0.direction, $0.entry) })

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 8) {
                    Text(directionalFamilyTitle(summary.kind))
                        .font(.subheadline.weight(.semibold))
                    if let group = directionalGroup(from: summary.kind) {
                        Button {
                            model.toggleDirectionalGroupPinned(group)
                        } label: {
                            Image(systemName: model.isDirectionalGroupPinned(group) ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(model.isDirectionalGroupPinned(group) ? "Unpin this directional group from right-click menu" : "Pin this directional group to right-click menu")
                    }
                }

                Text(directionalFamilyDescription(summary.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 5) {
                HStack {
                    Spacer(minLength: 0)
                    directionalDirectionBox(direction: .up, entry: byDirection[.up])
                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    directionalDirectionBox(direction: .left, entry: byDirection[.left])
                    directionalDirectionBox(direction: .down, entry: byDirection[.down])
                    directionalDirectionBox(direction: .right, entry: byDirection[.right])
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func directionalDirectionBox(
        direction: DirectionalShortcutFamilySummary.Direction,
        entry: ShortcutEntry?
    ) -> some View {
        if let entry {
            Button {
                model.runShortcut(entry)
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: directionArrowSymbolName(direction))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)

                    shortcutSymbolCaps(for: entry, glyphSize: 14, highlighted: false)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(minWidth: 74, maxWidth: 80, minHeight: 48)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help(model.shortcutExplanation(entry))
        } else {
            VStack(spacing: 3) {
                Image(systemName: directionArrowSymbolName(direction))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .frame(minWidth: 74, maxWidth: 80, minHeight: 48)
            .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
    }

    private func desktopShortcutFamilyCard(_ summary: DesktopShortcutFamilySummary) -> some View {
        let exampleLimit = summary.entries.count <= 4 ? 4 : 3
        let examples = Array(summary.entries.prefix(exampleLimit))
        let moreCount = max(0, summary.entries.count - examples.count)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(desktopFamilyTitle(summary.kind))
                        .font(.subheadline.weight(.semibold))
                    Text(desktopFamilyDescription(summary.kind))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if summary.kind == .goToDesktop {
                    Button("Use macOS Shortcut") {
                        model.openMissionControlKeyboardShortcuts()
                    }
                    .font(.caption)
                } else {
                    Text("Requires SA")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.1), in: Capsule())
                }
            }

            HStack(spacing: 6) {
                ForEach(examples, id: \.entry.id) { sample in
                    Button {
                        model.selectShortcut(sample.entry)
                    } label: {
                        HStack(alignment: .center, spacing: 6) {
                            Text(model.displayShortcutComboWords(sample.entry))
                                .font(.system(size: 11, weight: .semibold))
                            Text(model.displayShortcutComboSymbolsSpaced(sample.entry))
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(desktopExampleHelp(sample.entry, desktop: sample.desktop, kind: summary.kind))
                }
                if moreCount > 0 {
                    Text("+\(moreCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private func desktopShortcutFamilies(from entries: [ShortcutEntry]) -> [DesktopShortcutFamilySummary] {
        var goTo: [(ShortcutEntry, Int)] = []
        var moveAndFollow: [(ShortcutEntry, Int)] = []

        for entry in entries {
            if let desktop = desktopGoToTarget(from: entry.command), !entry.command.lowercased().contains("window --space") {
                goTo.append((entry, desktop))
                continue
            }
            if let desktop = desktopMoveAndFollowTarget(from: entry.command) {
                moveAndFollow.append((entry, desktop))
                continue
            }
        }

        let sortedGoTo = goTo.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.sourceLine < rhs.0.sourceLine : lhs.1 < rhs.1 }
        let sortedMove = moveAndFollow.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.0.sourceLine < rhs.0.sourceLine : lhs.1 < rhs.1 }

        var output: [DesktopShortcutFamilySummary] = []
        if !sortedGoTo.isEmpty {
            output.append(.init(kind: .goToDesktop, entries: sortedGoTo.map { ($0.0, $0.1) }))
        }
        if !sortedMove.isEmpty {
            output.append(.init(kind: .moveWindowToDesktopAndFollow, entries: sortedMove.map { ($0.0, $0.1) }))
        }
        return output
    }

    private func directionalShortcutFamilies(from entries: [ShortcutEntry]) -> [DirectionalShortcutFamilySummary] {
        var buckets: [DirectionalShortcutFamilySummary.Kind: [(ShortcutEntry, DirectionalShortcutFamilySummary.Direction)]] = [:]

        for entry in entries {
            guard let (kind, direction) = directionalShortcutKindAndDirection(from: entry.command) else { continue }
            buckets[kind, default: []].append((entry, direction))
        }

        var output: [DirectionalShortcutFamilySummary] = []
        for kind in DirectionalShortcutFamilySummary.Kind.allCases {
            guard let rawEntries = buckets[kind], !rawEntries.isEmpty else { continue }
            let sorted = rawEntries.sorted { lhs, rhs in
                if lhs.1.sortRank != rhs.1.sortRank { return lhs.1.sortRank < rhs.1.sortRank }
                return lhs.0.sourceLine < rhs.0.sourceLine
            }
            output.append(.init(kind: kind, entries: sorted.map { ($0.0, $0.1) }))
        }
        return output
    }

    private func directionalShortcutKindAndDirection(from command: String) -> (DirectionalShortcutFamilySummary.Kind, DirectionalShortcutFamilySummary.Direction)? {
        let c = command.lowercased()

        if let direction = cardinalDirection(from: c, west: "yabai -m window --focus west", east: "yabai -m window --focus east", north: "yabai -m window --focus north", south: "yabai -m window --focus south") {
            return (.focusWindow, direction)
        }
        if let direction = cardinalDirection(from: c, west: "yabai -m window --warp west", east: "yabai -m window --warp east", north: "yabai -m window --warp north", south: "yabai -m window --warp south") {
            return (.moveWindow, direction)
        }
        if let direction = cardinalDirection(from: c, west: "yabai -m window --swap west", east: "yabai -m window --swap east", north: "yabai -m window --swap north", south: "yabai -m window --swap south") {
            return (.swapWindow, direction)
        }

        if c.contains("yabai -m window --resize left:") { return (.resizeWindow, .left) }
        if c.contains("yabai -m window --resize right:") { return (.resizeWindow, .right) }
        if c.contains("yabai -m window --resize top:") { return (.resizeWindow, .up) }
        if c.contains("yabai -m window --resize bottom:") { return (.resizeWindow, .down) }

        return nil
    }

    private func cardinalDirection(
        from command: String,
        west: String,
        east: String,
        north: String,
        south: String
    ) -> DirectionalShortcutFamilySummary.Direction? {
        if command.contains(north) { return .up }
        if command.contains(west) { return .left }
        if command.contains(south) { return .down }
        if command.contains(east) { return .right }
        return nil
    }

    private func directionalFamilyTitle(_ kind: DirectionalShortcutFamilySummary.Kind) -> String {
        switch kind {
        case .focusWindow:
            return "Focus Window (Direction Keys)"
        case .moveWindow:
            return "Move Window in Layout (Direction Keys)"
        case .resizeWindow:
            return "Resize Window (Direction Keys)"
        case .swapWindow:
            return "Swap Window (Direction Keys)"
        }
    }

    private func directionalFamilyDescription(_ kind: DirectionalShortcutFamilySummary.Kind) -> String {
        switch kind {
        case .focusWindow:
            return "Use the I / J / K / L direction keys to move focus up, left, down, and right."
        case .moveWindow:
            return "Use the I / J / K / L direction keys to move the focused window to another tile position."
        case .resizeWindow:
            return "Use the I / J / K / L direction keys to resize the focused window up, left, down, and right."
        case .swapWindow:
            return "Use the I / J / K / L direction keys to swap with a neighboring window in a direction."
        }
    }

    private func directionalGroup(from kind: DirectionalShortcutFamilySummary.Kind) -> DirectionalShortcutGroup? {
        DirectionalShortcutGroup(rawValue: kind.rawValue)
    }

    private func directionArrowSymbolName(_ direction: DirectionalShortcutFamilySummary.Direction) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .left: return "arrow.left"
        case .down: return "arrow.down"
        case .right: return "arrow.right"
        }
    }

    @ViewBuilder
    private func shortcutSymbolCaps(
        for entry: ShortcutEntry,
        glyphSize: CGFloat,
        highlighted: Bool
    ) -> some View {
        let symbols = model.displayShortcutComboSymbols(entry)
        let glyphs = symbols.isEmpty ? [] : Array(symbols).map(String.init)
        HStack(spacing: 4) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
                Text(glyph)
                    .font(.system(size: glyphSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(minWidth: glyphSize + 6, minHeight: glyphSize + 4)
                    .background(
                        (highlighted ? Color.blue.opacity(0.10) : Color.primary.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
        }
        .lineLimit(1)
    }

    private func desktopFamilyTitle(_ kind: DesktopShortcutFamilySummary.Kind) -> String {
        switch kind {
        case .goToDesktop: return "Go to Desktop"
        case .moveWindowToDesktopAndFollow: return "Move Window to Desktop"
        }
    }

    private func desktopFamilyDescription(_ kind: DesktopShortcutFamilySummary.Kind) -> String {
        switch kind {
        case .goToDesktop:
            return "Switch to desktop number N. macOS can do this natively in Keyboard Shortcuts → Mission Control (no SIP changes needed)."
        case .moveWindowToDesktopAndFollow:
            return "Move the focused window to desktop N, then switch there. This is an advanced yabai desktop-control feature (scripting addition) and may not be worth enabling for many users."
        }
    }

    private func desktopExampleHelp(_ entry: ShortcutEntry, desktop: Int, kind: DesktopShortcutFamilySummary.Kind) -> String {
        switch kind {
        case .goToDesktop:
            return "\(model.displayShortcutComboWords(entry)) switches to Desktop \(desktop)."
        case .moveWindowToDesktopAndFollow:
            return "\(model.displayShortcutComboWords(entry)) moves the focused window to Desktop \(desktop), then switches there."
        }
    }

    private func desktopGoToTarget(from command: String) -> Int? {
        let c = command.lowercased()
        guard !c.contains("window --space") else { return nil }
        guard let range = c.range(of: "yabai -m space --focus ") else { return nil }
        let suffix = c[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    private func desktopMoveAndFollowTarget(from command: String) -> Int? {
        let c = command.lowercased()
        guard c.contains("yabai -m window --space ") else { return nil }
        guard let range = c.range(of: "yabai -m window --space ") else { return nil }
        let suffix = c[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    private func shortcutIntentGroup(_ entry: ShortcutEntry) -> String {
        let c = entry.command.lowercased()

        if c.contains("yabai -m window --space") {
            return "Experimental Desktop Move"
        }
        if c.contains("yabai -m space --focus") {
            return "Desktops"
        }
        if c.contains("yabai -m window --warp") {
            return "Window Placement"
        }
        if c.contains("yabai -m window --resize") {
            return "Window Size"
        }
        if c.contains("yabai -m window --toggle float") ||
            c.contains("yabai -m space --balance") ||
            c.contains("yabai -m space --layout") ||
            c.contains("yabai -m space --rotate") {
            return "Tiling & Layout"
        }
        if c.contains("yabai -m window --focus") {
            return "Focus"
        }
        if c.contains("yabai -m display") {
            return "Displays"
        }
        if c.contains("osascript") || c.contains("skhd -k") {
            return "Automation"
        }

        if let first = c.split(whereSeparator: \.isWhitespace).first {
            let token = String(first)
            if token.hasPrefix("/") || token.hasPrefix("~/") || token.hasPrefix("./") {
                return "Helpers & Scripts"
            }
        }
        if c.hasPrefix("open ") || c.contains(" open ") {
            return "Apps"
        }

        if entry.category == "Spaces" { return "Desktops" }
        if entry.category == "Windows" { return "Tiling & Layout" }
        return entry.category == "Other" ? "Other" : entry.category
    }

    private func shortcutGroupRank(_ group: String) -> Int {
        switch group {
        case "Desktops": return 0
        case "Window Placement": return 1
        case "Tiling & Layout": return 2
        case "Window Size": return 3
        case "Helpers & Scripts": return 4
        case "Apps": return 5
        case "Focus": return 6
        case "Displays": return 7
        case "Automation": return 8
        case "Other": return 98
        case "Experimental Desktop Move": return 99
        default: return 50
        }
    }

    private func shortcutGroupTitle(_ group: String) -> String {
        switch group {
        case "Experimental Desktop Move":
            return "Desktop Move (Experimental)"
        default:
            return group
        }
    }
}

struct ConfigDashboardView: View {
    @EnvironmentObject private var model: AppModel
    let showNavigationContainer: Bool

    init(showNavigationContainer: Bool = true) {
        self.showNavigationContainer = showNavigationContainer
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.managedConfigDraft },
            set: { model.updateManagedConfigDraft($0) }
        )
    }

    var body: some View {
        Group {
            if showNavigationContainer {
                NavigationStack {
                    dashboardBody
                        .navigationTitle("TilePilot")
                }
            } else {
                dashboardBody
            }
        }
    }

    private var dashboardBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                editorCard
                diffCard
                backupsCard
            }
            .padding()
        }
        .task {
            if model.configFilePath == nil && !model.isRefreshingConfig {
                await model.refreshConfig()
            }
        }
    }

    private var cardHeaderLabel: some View {
        Label("Config", systemImage: "slider.horizontal.3")
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Managed `skhdrc` Section", systemImage: "doc.badge.gearshape")
                        .font(.headline)
                    Spacer()
                    if model.isRefreshingConfig || model.isSavingConfig || model.isRestoringConfig {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("Edits only the TilePilot managed marker block. Unknown lines outside the markers are preserved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let path = model.configFilePath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label(model.configFileExists ? "skhdrc exists" : "skhdrc will be created", systemImage: model.configFileExists ? "checkmark.circle" : "plus.circle")
                        .font(.caption)
                        .foregroundStyle(model.configFileExists ? .green : .orange)
                    Label(model.configHasManagedSection ? "managed section found" : "managed section will be inserted", systemImage: model.configHasManagedSection ? "square.and.pencil" : "square.badge.plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(model.isManagedConfigDraftDirty ? "unsaved changes" : "saved draft", systemImage: model.isManagedConfigDraftDirty ? "pencil.circle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(model.isManagedConfigDraftDirty ? .orange : .green)
                }

                HStack(spacing: 10) {
                    Button(model.isRefreshingConfig ? "Reloading..." : "Reload From skhdrc") {
                        Task { await model.refreshConfig() }
                    }
                    .disabled(model.isRefreshingConfig || model.isSavingConfig || model.isRestoringConfig)

                    Button("Discard Unsaved Edits") {
                        model.resetManagedConfigDraft()
                    }
                    .disabled(!model.isManagedConfigDraftDirty || model.isSavingConfig || model.isRestoringConfig)

                    Button(model.isSavingConfig ? "Saving..." : "Save skhd Shortcuts") {
                        model.saveManagedConfigSection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSavingConfig || model.isRestoringConfig)
                }

                if let error = model.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                if let message = model.lastActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { cardHeaderLabel }
    }

    private var editorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Managed Section Editor")
                    .font(.headline)
                Text("Basic validation checks for malformed lines (heuristic). The app attempts a best-effort `skhd` restart after save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: draftBinding)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .padding(6)
                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Editor", systemImage: "pencil.and.outline")
        }
    }

    private var diffCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Managed Section Diff Preview")
                    .font(.headline)
                ScrollView {
                    Text(model.configDiffPreviewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 140, maxHeight: 220)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Preview", systemImage: "doc.text.magnifyingglass")
        }
    }

    private var backupsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Backups")
                        .font(.headline)
                    Spacer()
                    Button("Restore Latest") {
                        model.restoreLatestConfigBackup()
                    }
                    .disabled(model.configBackups.isEmpty || model.isRestoringConfig || model.isSavingConfig)
                }

                if model.configBackups.isEmpty {
                    Text("No backups yet. A backup is created before each save when `skhdrc` already exists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.configBackups.prefix(8))) { backup in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: backup.path).lastPathComponent)
                                    .font(.caption.weight(.semibold))
                                Text(backup.createdAt.formatted())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(backup.sizeBytes) bytes")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") {
                                model.restoreConfigBackup(backup)
                            }
                            .disabled(model.isRestoringConfig || model.isSavingConfig)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Backup / Restore", systemImage: "clock.arrow.circlepath")
        }
    }
}

struct SetupDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    if let snapshot = model.bootstrapSnapshot {
                        checklistCard(title: "Core Install Requirements", items: model.setupCoreItems)
                        checklistCard(title: "Services + Integration", items: model.setupServiceItems)
                        installerCard(snapshot: snapshot)
                        manualStepsCard
                    } else {
                        EmptyStateView(
                            title: "Scan Setup",
                            systemImage: "shippingbox",
                            message: "Check for Homebrew, yabai, skhd, and launch services. Then run the installer helper in Terminal for a fresh mac setup."
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("TilePilot")
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label("Fresh Mac Bootstrap", systemImage: "shippingbox")
                    .font(.headline)
                Text(model.setupSummaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("This launches a Terminal installer that can install Homebrew, `yabai`, and `skhd`. Some steps require admin approval and user confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button(model.isLaunchingSetupInstaller ? "Opening Installer..." : "Install Dependencies") {
                        model.runSetupInstallerInTerminal()
                    }
                    .disabled(model.isLaunchingSetupInstaller)

                    Button(model.isRefreshingBootstrap ? "Checking..." : "Run Setup Check") {
                        Task { await model.refreshBootstrapSetup() }
                    }
                    .disabled(model.isRefreshingBootstrap)

                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                }

                if let installerURL = model.lastSetupInstallerURL {
                    Text("Installer script: \(installerURL.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let error = model.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let message = model.lastActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Setup Assistant", systemImage: "wand.and.stars")
        }
    }

    private func checklistCard(title: String, items: [SetupCheckItem]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text("Run Check Setup to populate this list.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: symbol(for: item.state))
                                .foregroundStyle(color(for: item.state))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                setupActionsRow(for: item)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: "list.bullet.clipboard")
        }
    }

    private func installerCard(snapshot: SetupBootstrapSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Install Dependencies in Terminal")
                    .font(.headline)
                Text("The app writes a reusable `.command` script and opens it in Terminal. This keeps installs explicit and works on fresh macOS systems.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let brewPrefix = snapshot.brewPrefix, !brewPrefix.isEmpty {
                    Text("Detected Homebrew prefix: \(brewPrefix)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(model.isLaunchingSetupInstaller ? "Opening Installer..." : "Install Dependencies") {
                        model.runSetupInstallerInTerminal()
                    }
                    .disabled(model.isLaunchingSetupInstaller)

                    Button("Keyboard Shortcuts (Mission Control)") {
                        model.openMissionControlKeyboardShortcuts()
                    }

                    Button(model.isLaunchingScriptingAdditionFix ? "Opening SA Fix..." : "Fix Scripting Addition") {
                        model.runScriptingAdditionRepairInTerminal()
                    }
                    .disabled(model.isLaunchingScriptingAdditionFix)

                    Button("Request Accessibility Access") {
                        model.requestAccessibilityAccessPrompt()
                    }

                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Installer", systemImage: "terminal")
        }
    }

    private var manualStepsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Manual Steps Still Required")
                    .font(.headline)
                Text("Some macOS capabilities cannot be safely automated from a GUI app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("1. Grant Accessibility to TilePilot (and yabai/skhd if your setup requires it).")
                Text("2. Confirm Mission Control settings in Health.")
                Text("3. Desktop switching can use macOS Mission Control keyboard shortcuts (no SIP changes required).")
                Text("4. Moving windows between desktops with yabai shortcuts requires the yabai scripting addition (and may require SIP configuration).")

                HStack {
                    Button("Open Mission Control Settings") { model.openMissionControlSettings() }
                    Button("Keyboard Shortcuts (Mission Control)") { model.openMissionControlKeyboardShortcuts() }
                    Button(model.isLaunchingScriptingAdditionFix ? "Opening SA Fix..." : "Fix Scripting Addition") {
                        model.runScriptingAdditionRepairInTerminal()
                    }
                    .disabled(model.isLaunchingScriptingAdditionFix)
                    Button("Run Setup Check") {
                        Task { await model.refreshDoctor() }
                    }
                    .disabled(model.isRefreshing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("What Requires You", systemImage: "person.badge.key")
        }
    }

    @ViewBuilder
    private func setupActionsRow(for item: SetupCheckItem) -> some View {
        HStack(spacing: 8) {
            switch item.id {
            case "xcode-clt":
                if item.state == .missing {
                    Button("Install CLT") { model.requestXcodeCLTInstallPrompt() }
                } else {
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                }
            case "homebrew", "yabai-binary", "skhd-binary", "brew-tap-koekeishiya":
                Button("Install Dependencies") { model.runSetupInstallerInTerminal() }
                if item.state != .missing {
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                }
            case "brew-service-yabai":
                if item.state == .installed {
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                } else {
                    Button("Start Service") { model.startBrewServiceYabai() }
                    Button("Install Dependencies") { model.runSetupInstallerInTerminal() }
                }
            case "brew-service-skhd":
                if item.state == .installed {
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                } else {
                    Button("Start Service") { model.startBrewServiceSkhd() }
                    Button("Install Dependencies") { model.runSetupInstallerInTerminal() }
                }
            case "start-at-logon":
                if item.state == .installed {
                    Button("Login Items") { model.openLoginItemsSettings() }
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                } else {
                    Button("Enable") { model.enableStartAtLogon() }
                    Button("Login Items") { model.openLoginItemsSettings() }
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                }
            case "accessibility-permission":
                if item.state == .installed {
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                } else {
                    Button("Request Access") { model.requestAccessibilityAccessPrompt() }
                    Button("Open Settings") { model.openAccessibilitySettings() }
                    Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
                }
            default:
                Button("Recheck") { Task { await model.refreshBootstrapSetup() } }
            }
        }
        .font(.caption)
        .buttonStyle(.borderless)
        .padding(.top, 2)
    }

    private func color(for state: SetupCheckState) -> Color {
        switch state {
        case .installed: return .green
        case .warning: return .orange
        case .missing: return .red
        case .unknown: return .yellow
        }
    }

    private func symbol(for state: SetupCheckState) -> String {
        switch state {
        case .installed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .missing: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

struct HealthDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    if let snapshot = model.doctorSnapshot {
                        checklistCard(title: "Core Features Available Now", items: model.coreChecklistItems)
                        checklistCard(title: "Advanced Features / Optional Dependencies", items: model.advancedChecklistItems)
                        recoveryCard(snapshot: snapshot)
                        systemProfileCard(snapshot.systemProfile)
                        capabilityCard(snapshot.capabilities)
                        missionControlCard(snapshot.missionControlChecks)
                        if !snapshot.compatibilityWarnings.isEmpty {
                            warningsCard(snapshot.compatibilityWarnings)
                        }
                    } else {
                        EmptyStateView(
                            title: "Run Setup Check",
                            systemImage: "stethoscope",
                            message: "Run Setup Check to populate setup guidance, recovery actions, and diagnostics."
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("TilePilot")
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.healthBadgeTitle, systemImage: model.healthBadgeSymbol)
                    .font(.headline)
                Text(model.statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let url = model.lastExportURL {
                    Text("Last diagnostics export: \(url.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let error = model.lastErrorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let message = model.lastActionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Health Status", systemImage: "heart.text.square")
        }
    }

    private func systemProfileCard(_ profile: SystemProfile) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow { Text("macOS"); Text(profile.macOSVersion).foregroundStyle(.secondary) }
                GridRow { Text("Build"); Text(profile.macOSBuild ?? "Unknown").foregroundStyle(.secondary) }
                GridRow { Text("Arch"); Text(profile.arch).foregroundStyle(.secondary) }
                GridRow { Text("yabai"); Text(profile.yabaiVersion ?? "Not detected").foregroundStyle(.secondary) }
                GridRow { Text("skhd"); Text(profile.skhdVersion ?? "Not detected").foregroundStyle(.secondary) }
                GridRow { Text("Detected"); Text(profile.detectedAt.formatted()).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("System Profile", systemImage: "desktopcomputer")
        }
    }

    private func capabilityCard(_ capabilities: [CapabilityState]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(capabilities) { capability in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .center, spacing: 8) {
                            Circle()
                                .fill(color(for: capability.status))
                                .frame(width: 9, height: 9)
                            Text(capability.key)
                                .font(.headline)
                            Spacer()
                            Text(capability.status.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(capability.message)
                            .font(.subheadline)
                        if !capability.remediationSteps.isEmpty {
                            Text("Next: " + capability.remediationSteps.joined(separator: " "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Capabilities", systemImage: "checklist")
        }
    }

    private func missionControlCard(_ checks: [MissionControlCheck]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(checks) { check in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: symbol(for: check.status))
                            .foregroundStyle(color(for: check.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.key)
                                .font(.headline)
                            Text(check.message)
                                .font(.subheadline)
                            Text("Expected: \(check.expected) · Actual: \(check.actual ?? "unknown")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mission Control Checks", systemImage: "gearshape.2")
        }
    }

    private func warningsCard(_ warnings: [String]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Compatibility Warnings", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private func checklistCard(title: String, items: [DoctorChecklistItem]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    Text("Run Setup Check to populate checklist items.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: symbol(for: item.status))
                                .foregroundStyle(color(for: item.status))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.detail)
                                    .font(.subheadline)
                                if let first = item.remediation.first, item.status != .available {
                                    Text("Next: \(first)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if item.title == "Accessibility permission", item.status != .available {
                                    Button("Open Accessibility Settings") {
                                        model.openAccessibilitySettings()
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                }
                                if item.title.localizedCaseInsensitiveContains("scripting addition"), item.status != .available {
                                    HStack(spacing: 8) {
                                        Button("Keyboard Shortcuts (Mission Control)") {
                                            model.openMissionControlKeyboardShortcuts()
                                        }
                                        Button(model.isLaunchingScriptingAdditionFix ? "Opening Fix..." : "Fix Scripting Addition") {
                                            model.runScriptingAdditionRepairInTerminal()
                                        }
                                        .disabled(model.isLaunchingScriptingAdditionFix)
                                        Button("Recheck") {
                                            Task { await model.refreshDoctor() }
                                        }
                                        .disabled(model.isRefreshing)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: "checklist")
        }
    }

    private func recoveryCard(snapshot: DoctorSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Guided recovery actions")
                    .font(.headline)
                Text("Best-effort, non-privileged actions for common setup failures.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Run Setup Check") {
                        Task { await model.refreshDoctor() }
                    }
                    .disabled(model.isRefreshing)

                    Button("Copy Issue Summary") {
                        model.copyIssueReadySummary()
                    }

                    Button("Export Diagnostics") {
                        model.exportDiagnostics()
                    }
                }

                HStack {
                    Button("Request Accessibility Access") {
                        model.requestAccessibilityAccessPrompt()
                    }
                    Button("Keyboard Shortcuts (Mission Control)") {
                        model.openMissionControlKeyboardShortcuts()
                    }
                    Button(model.isLaunchingScriptingAdditionFix ? "Opening SA Fix..." : "Fix Scripting Addition") {
                        model.runScriptingAdditionRepairInTerminal()
                    }
                    .disabled(model.isLaunchingScriptingAdditionFix)
                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    Button("Open Mission Control Settings") {
                        model.openMissionControlSettings()
                    }
                    Button("Open System Settings") {
                        model.openSystemSettings()
                    }
                }

                HStack {
                    Button("Restart yabai (Best Effort)") {
                        model.restartYabaiBestEffort()
                    }
                    .disabled(model.isRefreshing)

                    Button("Restart skhd (Best Effort)") {
                        model.restartSkhdBestEffort()
                    }
                    .disabled(model.isRefreshing)
                }

                if snapshot.healthBadge == .blocked {
                    Text("Blocked commonly means missing yabai/skhd, missing permissions, or a broken yabai scripting addition. Desktop switching can still use macOS Mission Control keyboard shortcuts.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Recovery", systemImage: "wrench.and.screwdriver")
        }
    }

    private func color(for status: CapabilityStatus) -> Color {
        switch status {
        case .available: return .green
        case .unknown: return .yellow
        case .degraded: return .orange
        case .unsupported: return .brown
        case .blocked: return .red
        }
    }

    private func color(for status: MissionControlCheckStatus) -> Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .unknown: return .yellow
        }
    }

    private func symbol(for status: MissionControlCheckStatus) -> String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func symbol(for status: CapabilityStatus) -> String {
        switch status {
        case .available: return "checkmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .degraded: return "minus.circle.fill"
        case .unsupported: return "slash.circle.fill"
        case .blocked: return "xmark.circle.fill"
        }
    }
}

struct CommandLogView: View {
    @EnvironmentObject private var model: AppModel
    let showNavigationContainer: Bool

    init(showNavigationContainer: Bool = true) {
        self.showNavigationContainer = showNavigationContainer
    }

    var body: some View {
        Group {
            if showNavigationContainer {
                NavigationStack {
                    listBody
                        .navigationTitle("TilePilot")
                }
            } else {
                listBody
            }
        }
    }

    private var listBody: some View {
        List(model.commandLogs) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.command)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Text(statusLabel(entry))
                        .font(.caption)
                        .foregroundStyle(statusColor(entry))
                }

                Text("\(entry.startedAt.formatted(date: .omitted, time: .standard)) · \(entry.durationMs) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !entry.stderrSnippet.isEmpty {
                    Text(entry.stderrSnippet)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                    if let hint = hint(for: entry) {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                } else if !entry.stdoutSnippet.isEmpty {
                    Text(entry.stdoutSnippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .overlay {
            if model.commandLogs.isEmpty {
                EmptyStateView(
                    title: "No Command Logs",
                    systemImage: "list.bullet.rectangle",
                    message: "Run System Recheck to populate diagnostics."
                )
            }
        }
    }

    private func statusLabel(_ entry: CommandLogEntry) -> String {
        if entry.errorType == .none, entry.exitStatus == 0 {
            return "OK"
        }
        return entry.errorType.rawValue
    }

    private func statusColor(_ entry: CommandLogEntry) -> Color {
        entry.errorType == .none ? .green : .orange
    }

    private func hint(for entry: CommandLogEntry) -> String? {
        let stderr = entry.stderrSnippet.lowercased()
        let command = entry.command.lowercased()

        if command.contains("--check-sa"),
           stderr.contains("not a valid option") || stderr.contains("unknown option") || stderr.contains("unrecognized option") {
            return "Optional compatibility check not supported by this yabai version. Safe to ignore."
        }

        if command.contains("yabai"), stderr.contains("no such file or directory") {
            return "yabai is not installed yet. Use System -> Install Dependencies."
        }

        if command.contains("yabai"), stderr.contains("could not connect") {
            return "yabai is installed but not running. Start/restart the yabai service."
        }

        return nil
    }
}

struct PlaceholderTabView: View {
    let title: String
    let bodyText: String

    var body: some View {
        EmptyStateView(title: title, systemImage: "hammer", message: bodyText)
            .padding()
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct SettingsPlaceholderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TilePilot Settings")
                .font(.title2.bold())
            Text("Phase 1 ships the foundation and setup/health shell. App settings will expand in later phases.")
                .foregroundStyle(.secondary)
            Text("Phase 2 adds setup/recovery checklist and guided actions in the Health tab.")
                .foregroundStyle(.secondary)
            Text("Current Health: \(model.healthBadgeTitle)")
            Spacer()
        }
        .padding()
        .frame(minWidth: 420, minHeight: 240)
        .task {
            model.startIfNeeded()
        }
    }
}
