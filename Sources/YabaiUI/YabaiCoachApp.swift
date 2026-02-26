import AppKit
import SwiftUI

enum CoachTab: Hashable {
    case now
    case windowBehavior
    case actions
    case shortcuts
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

struct CoachRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: CoachTab = .now
    @State private var hasAppliedInitialTabSelection = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NowDashboardView()
                .tabItem { Label("TilePilot", systemImage: "rectangle.3.group") }
                .tag(CoachTab.now)

            WindowBehaviorDashboardView()
                .tabItem { Label("Window Behavior", systemImage: "hand.raised.square") }
                .tag(CoachTab.windowBehavior)

            ActionsDashboardView()
                .tabItem { Label("Actions", systemImage: "square.grid.2x2") }
                .tag(CoachTab.actions)

            ShortcutsDashboardView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(CoachTab.shortcuts)

            ConfigDashboardView()
                .tabItem { Label("Config", systemImage: "slider.horizontal.3") }
                .tag(CoachTab.config)

            HealthDashboardView()
                .tabItem { Label("Health", systemImage: "stethoscope") }
                .tag(CoachTab.health)

            SetupDashboardView()
                .tabItem { Label("Setup", systemImage: "shippingbox") }
                .tag(CoachTab.setup)

            CommandLogView()
                .tabItem { Label("Logs", systemImage: "list.bullet.rectangle") }
                .tag(CoachTab.logs)
        }
        .onChange(of: model.requestedCoachTab) { newValue in
            if let newValue {
                selectedTab = newValue
                _ = model.consumeRequestedCoachTab()
            }
        }
        .task {
            if !hasAppliedInitialTabSelection {
                selectedTab = model.consumeShouldStartOnSetupTab() ? .setup : .now
                hasAppliedInitialTabSelection = true
            }
            model.startIfNeeded()
            if model.doctorSnapshot == nil {
                await model.refreshDoctor()
            }
        }
    }
}

struct NowDashboardView: View {
    @EnvironmentObject private var model: AppModel

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

                        focusedWindowControls(snapshot)

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

    @ViewBuilder
    private func focusedWindowControls(_ snapshot: LiveStateSnapshot) -> some View {
        if snapshot.source == .yabai, let focused = model.focusedWindowState {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AppNameWithIconView(appName: focused.app)
                            .font(.headline)
                        Text(focused.title.isEmpty ? "Untitled" : focused.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Button("Tile") { model.tileFocusedWindowNow() }
                        Button("Float") { model.floatFocusedWindowNow() }
                        Button("Toggle") { model.toggleFocusedWindowTiling() }
                        Spacer(minLength: 0)
                    }
                }
            } label: {
                Label("Focused Window", systemImage: "macwindow")
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
        let visibleWindows = snapshot.windows.filter { window in
            window.isVisible && !window.isMinimized && !window.isHidden
        }
        let windowsBySpace = Dictionary(grouping: visibleWindows, by: \.space)
        let visibleWindowCountByDisplay = Dictionary(grouping: visibleWindows, by: \.display).mapValues(\.count)
        let visibleWindowCountBySpace = Dictionary(grouping: visibleWindows, by: \.space).mapValues(\.count)

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if snapshot.displays.isEmpty {
                    Text("No displays returned by yabai.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.displays) { display in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(display.name, systemImage: display.focused ? "display.and.arrow.down" : "display")
                                    .font(.headline)
                                Spacer()
                                Text("\(visibleWindowCountByDisplay[display.id] ?? 0) windows")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            let displaySpaces = (spacesByDisplay[display.id] ?? []).sorted { $0.index < $1.index }
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
                                            Text("\(visibleWindowCountBySpace[space.index] ?? 0) windows")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        let spaceWindows = (windowsBySpace[space.index] ?? []).sorted { lhs, rhs in
                                            if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                                            return lhs.id < rhs.id
                                        }

                                        if spaceWindows.isEmpty {
                                            Text("No windows")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            ForEach(spaceWindows) { window in
                                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                                    AppNameWithIconView(appName: window.app)
                                                        .font(.caption.weight(.semibold))
                                                    if window.focused {
                                                        statusPill("Focused", color: .blue)
                                                    } else if window.floating {
                                                        statusPill("Floating", color: .orange)
                                                    }
                                                    Text(window.title.isEmpty ? "Untitled" : window.title)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                }
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
            .navigationTitle("Window Behavior")
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
                Text("Controls whether moving the mouse over a window changes focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Hover Focus", selection: Binding(
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
                Text("If your cursor used to move by itself, that was a different yabai setting (`mouse_follows_focus`), not this one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Disable Hover Focus Now") { model.disableHoverFocus() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Hover Focus", systemImage: "cursorarrow.motionlines")
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
                            Text("Workspace-level actions are disabled in degraded mode. Focus/window actions may still be available when `yabai` query access remains healthy.")
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
            .navigationTitle("Actions")
        }
    }

    private var actionsHeaderCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Click-first Actions", systemImage: "cursorarrow.click")
                        .font(.headline)
                    Spacer()
                    if let action = model.activeActionID {
                        Text("Running: \(actionLabel(action))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Every action is capability-gated and shows an explicit disabled reason when unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

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

    private func actionCard(_ card: CoachActionCard) -> some View {
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
                    model.performCoachAction(card.id)
                }
                .disabled(!card.enabled || model.activeActionID != nil)
            }

            if !card.requiredCapabilities.isEmpty {
                Text("Requires: " + card.requiredCapabilities.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private func buttonTitle(for card: CoachActionCard) -> String {
        if model.activeActionID == card.id { return "Running..." }
        return "Run"
    }

    private func actionLabel(_ action: CoachActionID) -> String {
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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerCard
                        searchCard

                        if !model.shortcutParseIssues.isEmpty {
                            issuesCard
                        }

                        shortcutsListCard
                    }
                    .padding()
                }
            }
            .navigationTitle("Shortcuts")
            .task {
                if model.shortcutEntries.isEmpty && !model.isRefreshingShortcuts {
                    await model.refreshShortcuts()
                }
            }
        }
    }

    private var filteredEntries: [ShortcutEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return model.shortcutEntries }
        return model.shortcutEntries.filter { entry in
            entry.combo.lowercased().contains(query) ||
            entry.command.lowercased().contains(query) ||
            entry.category.lowercased().contains(query)
        }
    }

    private var groupedEntries: [(String, [ShortcutEntry])] {
        let grouped = Dictionary(grouping: filteredEntries, by: \.category)
        return grouped.keys.sorted().map { key in
            (key, grouped[key]?.sorted { lhs, rhs in
                if lhs.combo != rhs.combo { return lhs.combo < rhs.combo }
                return lhs.sourceLine < rhs.sourceLine
            } ?? [])
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Shortcuts", systemImage: "keyboard")
                        .font(.headline)
                    Spacer()
                    if model.isRefreshingShortcuts {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text("Parses `~/.config/skhd/skhdrc` line-by-line and tolerates malformed lines.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let path = model.shortcutFilePath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    Button(model.isRefreshingShortcuts ? "Reloading..." : "Reload Shortcuts") {
                        Task { await model.refreshShortcuts() }
                    }
                    .disabled(model.isRefreshingShortcuts)

                    Text("\(filteredEntries.count) shown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Source", systemImage: "doc.text")
        }
    }

    private var searchCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search combo, command, or category", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Text("Examples: `cmd - h`, `space --focus`, `window --toggle float`")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Search", systemImage: "magnifyingglass")
        }
    }

    private var issuesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.shortcutParseIssues.prefix(10)), id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if model.shortcutParseIssues.count > 10 {
                    Text("\(model.shortcutParseIssues.count - 10) more issues hidden")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Parse Issues", systemImage: "exclamationmark.triangle.fill")
        }
    }

    private var shortcutsListCard: some View {
        GroupBox {
            if filteredEntries.isEmpty {
                EmptyStateView(
                    title: model.shortcutEntries.isEmpty ? "No shortcuts loaded" : "No matching shortcuts",
                    systemImage: "keyboard",
                    message: model.shortcutEntries.isEmpty
                        ? "Reload after creating `skhdrc`, or check the parse issues above."
                        : "Try a broader search query."
                )
                .frame(minHeight: 180)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedEntries, id: \.0) { category, entries in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category)
                                .font(.headline)
                            ForEach(entries) { entry in
                                shortcutRow(entry)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Label("Parsed Shortcuts", systemImage: "list.bullet")
        }
    }

    private func shortcutRow(_ entry: ShortcutEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.combo)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.command)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Text("Line \(entry.sourceLine)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let warning = entry.warning {
                            Text(warning)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }
                }

                Spacer()

                VStack(spacing: 6) {
                    Button("Copy Combo") {
                        model.copyShortcutCombo(entry)
                    }
                    .buttonStyle(.borderless)

                    Button("Copy Cmd") {
                        model.copyShortcutCommand(entry)
                    }
                    .buttonStyle(.borderless)
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct ConfigDashboardView: View {
    @EnvironmentObject private var model: AppModel

    private var draftBinding: Binding<String> {
        Binding(
            get: { model.managedConfigDraft },
            set: { model.updateManagedConfigDraft($0) }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    editorCard
                    diffCard
                    backupsCard
                }
                .padding()
            }
            .navigationTitle("Config")
            .task {
                if model.configFilePath == nil && !model.isRefreshingConfig {
                    await model.refreshConfig()
                }
            }
        }
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
        } label: {
            Label("Config MVP", systemImage: "slider.horizontal.3")
        }
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
            .navigationTitle("Setup")
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
                Text("3. Optional advanced yabai features require scripting-addition setup and SIP configuration.")

                HStack {
                    Button("Open Mission Control Settings") { model.openMissionControlSettings() }
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
            .navigationTitle("Health")
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
                    Text("Blocked commonly means missing Accessibility permission or a missing yabai/skhd binary.")
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

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Command Log")
            .overlay {
                if model.commandLogs.isEmpty {
                    EmptyStateView(
                        title: "No Command Logs",
                        systemImage: "list.bullet.rectangle",
                        message: "Run Setup Check to populate command diagnostics."
                    )
                }
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
            return "yabai is not installed yet. Use Setup -> Install Dependencies."
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
