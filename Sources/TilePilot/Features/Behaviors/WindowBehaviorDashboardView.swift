import SwiftUI

struct WindowBehaviorDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newNeverTileApp: String = ""
    @State private var newAlwaysTileApp: String = ""
    @State private var selectedExplainer: BehaviorExplainerTopic = .desktopTiling

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        precedenceCard
                        behaviorExplainerCard(proxy: proxy)
                        mouseDraggingCard
                        desktopBehaviorCard
                            .id(BehaviorScrollTarget.desktopTiling)
                        defaultBehaviorCard
                        appRulesCard
                            .id(BehaviorScrollTarget.appRules)
                        pointerFocusCard
                            .id(BehaviorScrollTarget.focusAndCursor)
                    }
                    .padding()
                }
            }
            .navigationTitle("TilePilot")
            .safeAreaInset(edge: .bottom) {
                if model.isAppRuleListApplyRequired {
                    VStack(spacing: 0) {
                        Divider()
                        applyBar
                            .padding(.horizontal)
                            .padding(.top, 10)
                            .padding(.bottom, 10)
                    }
                    .background(.ultraThinMaterial)
                }
            }
            .task { await model.refreshWindowBehaviorConfig() }
        }
    }

    private func behaviorExplainerCard(proxy: ScrollViewProxy) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pick one concept. The diagram shows what changes after you turn it on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $selectedExplainer) {
                    ForEach(BehaviorExplainerTopic.allCases) { topic in
                        Text(topic.displayTitle).tag(topic)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedExplainer.summary)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                selectedExplainer.diagram

                HStack {
                    Button(selectedExplainer.buttonTitle) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(selectedExplainer.scrollTarget, anchor: .top)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Advanced Concepts", systemImage: "sparkles.rectangle.stack")
        }
    }

    private var precedenceCard: some View {
        GroupBox {
            Text("Tiling decisions run in order: Desktop behavior -> App behavior -> Window override.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Behavior Order", systemImage: "arrow.triangle.branch")
        }
    }

    private var desktopBehaviorCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose whether each desktop auto-tiles windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("On = tiled layout · Off = floating layout")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let snapshot = model.liveStateSnapshot, snapshot.source == .yabai, !snapshot.degraded {
                    let displayByID = Dictionary(uniqueKeysWithValues: snapshot.displays.map { ($0.id, $0.name) })
                    let spaces = snapshot.spaces.sorted { lhs, rhs in
                        if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                        return lhs.index < rhs.index
                    }
                    ForEach(spaces, id: \.index) { space in
                        let enabled = model.desktopTilingEnabled(spaceIndex: space.index) ?? (((space.layout ?? "").lowercased()) != "float")
                        let disabledReason = model.desktopTilingDisabledReason(spaceIndex: space.index)
                        let displayName = displayByID[space.displayId] ?? "Display \(space.displayId)"
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                (
                                    Text("Desktop \(space.index) · \(displayName)") +
                                    (space.focused
                                     ? Text(" (current)").foregroundColor(.blue)
                                     : Text(""))
                                )
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            }
                            .frame(width: 330, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { model.desktopTilingEnabled(spaceIndex: space.index) ?? enabled },
                                set: { model.setDesktopTilingEnabled(spaceIndex: space.index, enabled: $0) }
                            )) {
                                Text("On").tag(true)
                                Text("Off").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 120)
                            .disabled(disabledReason != nil)
                            Spacer(minLength: 0)
                        }
                        if let disabledReason {
                            Text(disabledReason)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }

                    let allDisabledReason = spaces.compactMap { model.desktopTilingDisabledReason(spaceIndex: $0.index) }.first
                    let allEnabled = spaces.allSatisfy { space in
                        model.desktopTilingEnabled(spaceIndex: space.index) ?? (((space.layout ?? "").lowercased()) != "float")
                    }
                    let anyEnabled = spaces.contains { space in
                        model.desktopTilingEnabled(spaceIndex: space.index) ?? (((space.layout ?? "").lowercased()) != "float")
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("All Desktops")
                                .font(.subheadline.weight(.semibold))
                            if anyEnabled && !allEnabled {
                                Text("Mixed state")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 330, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { allEnabled },
                            set: { model.setAllDesktopTilingEnabled(enabled: $0) }
                        )) {
                            Text("On").tag(true)
                            Text("Off").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                        .disabled(allDisabledReason != nil)
                        Spacer(minLength: 0)
                    }
                    if let allDisabledReason {
                        Text(allDisabledReason)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Desktop tiling controls are available when yabai live desktop mapping is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Desktop Auto-Tiling", systemImage: "rectangle.3.group")
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

                Text("When a window is switched to Floating, TilePilot brings it to the front.")
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

                if let autosaveError = model.windowBehaviorAutosaveErrorMessage {
                    Text(autosaveError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if let autosaveMessage = model.windowBehaviorAutosaveActionMessage {
                    Text(autosaveMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("App Defaults", systemImage: "square.grid.3x3.topleft.filled")
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
            Label("Focus & Cursor", systemImage: "cursorarrow.motionlines")
        }
    }

    private var appRulesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved app behaviors are listed here and persist even when those apps are not currently open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Always Tile works when desktop tiling is On.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                listEditor(
                    title: "Never Tile Apps",
                    items: model.stagedNeverTileApps,
                    newValue: $newNeverTileApp,
                    addAction: { model.addStagedNeverTileApp(newNeverTileApp); newNeverTileApp = "" },
                    removeAction: { model.removeStagedNeverTileApp($0) }
                )

                Divider()

                listEditor(
                    title: "Always Tile Apps",
                    items: model.stagedAlwaysTileApps,
                    newValue: $newAlwaysTileApp,
                    addAction: { model.addStagedAlwaysTileApp(newAlwaysTileApp); newAlwaysTileApp = "" },
                    removeAction: { model.removeStagedAlwaysTileApp($0) }
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
                        Text("Keep-on-top policy applies only when app windows are floating.")
                            .font(.caption2)
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
            Label("App Behavior", systemImage: "list.bullet.clipboard")
        }
    }

    private var mouseDraggingCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Hold the modifier, click a window, then drag.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                behaviorMenuRow(
                    title: "Modifier Key",
                    detail: "Hold this key while clicking and dragging a window.",
                    selection: Binding(
                        get: { model.windowBehaviorPolicyDraft.mouseModifier },
                        set: { model.updateMouseModifierDraft($0) }
                    )
                )

                behaviorMenuRow(
                    title: "Modifier + Left Click + Drag",
                    detail: "Choose what happens when you hold the modifier, left-click a window, and drag it.",
                    selection: Binding(
                        get: { model.windowBehaviorPolicyDraft.mouseAction1 },
                        set: { model.updateMouseAction1Draft($0) }
                    )
                )

                behaviorMenuRow(
                    title: "Modifier + Right Click + Drag",
                    detail: "Choose what happens when you hold the modifier, right-click a window, and drag it.",
                    selection: Binding(
                        get: { model.windowBehaviorPolicyDraft.mouseAction2 },
                        set: { model.updateMouseAction2Draft($0) }
                    )
                )

                behaviorMenuRow(
                    title: "Dragged Tiled Window Dropped On Another",
                    detail: "Only applies to tiled windows. Drag one tiled window onto another and release near the center. Swap trades places. Stack groups them together.",
                    selection: Binding(
                        get: { model.windowBehaviorPolicyDraft.mouseDropAction },
                        set: { model.updateMouseDropActionDraft($0) }
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Mouse Dragging & Drop", systemImage: "arrow.up.left.and.arrow.down.right")
        }
    }

    private var applyBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Apply App Rule List Changes") { model.applyStagedAppRuleListChanges() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSavingYabaiConfig || model.isRestoringYabaiConfig || model.isApplyingStagedAppRules)
                Button("Discard List Changes") { model.discardStagedAppRuleListChanges() }
                    .disabled(model.isSavingYabaiConfig || model.isApplyingStagedAppRules)
                Spacer()
                if model.isApplyingStagedAppRules || model.isSavingYabaiConfig || model.isRestoringYabaiConfig || model.isRefreshingYabaiConfig {
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

    private func behaviorMenuRow<Value: CaseIterable & Hashable>(
        title: String,
        detail: String,
        selection: Binding<Value>
    ) -> some View where Value.AllCases: RandomAccessCollection, Value: BehaviorOptionDisplayable {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity, alignment: .leading)

                Picker("", selection: selection) {
                    ForEach(Array(Value.allCases), id: \.self) { value in
                        Text(value.pickerDisplayName).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .trailing)
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum BehaviorScrollTarget: String, Hashable {
    case desktopTiling
    case appRules
    case focusAndCursor
}

private enum BehaviorExplainerTopic: String, CaseIterable, Identifiable {
    case desktopTiling
    case appRules
    case hoverFocus

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .desktopTiling: return "Desktop Tiling"
        case .appRules: return "App Rules"
        case .hoverFocus: return "Hover Focus"
        }
    }

    var summary: String {
        switch self {
        case .desktopTiling:
            return "Desktop Auto-Tiling decides whether windows on a desktop snap into tiles or stay free-floating."
        case .appRules:
            return "App rules override the global default for specific apps, so one app can stay tiled or floating even when most others do not."
        case .hoverFocus:
            return "Hover Focus changes focus when your pointer crosses windows. Cursor Follows Focus moves the pointer to the focused window."
        }
    }

    var buttonTitle: String {
        switch self {
        case .desktopTiling: return "Jump to Desktop Auto-Tiling"
        case .appRules: return "Jump to App Behavior"
        case .hoverFocus: return "Jump to Focus & Cursor"
        }
    }

    var scrollTarget: BehaviorScrollTarget {
        switch self {
        case .desktopTiling: return .desktopTiling
        case .appRules: return .appRules
        case .hoverFocus: return .focusAndCursor
        }
    }

    @ViewBuilder
    var diagram: some View {
        switch self {
        case .desktopTiling:
            DesktopAutoTilingExplainerDiagram()
        case .appRules:
            AppRulesExplainerDiagram()
        case .hoverFocus:
            HoverFocusExplainerDiagram()
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
                            .frame(minWidth: 170, idealWidth: 210, maxWidth: 250, alignment: .leading)
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
                        .frame(width: 116)
                        Picker("", selection: Binding(
                            get: { model.appForegroundPolicy(for: app) },
                            set: { model.setAppForegroundPolicy($0, for: app) }
                        )) {
                            ForEach(AppForegroundPolicy.allCases, id: \.self) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 190)
                        Spacer(minLength: 0)
                    }
                    if model.appTilingBehavior(for: app) == .alwaysTile,
                       let conflictDesktop = model.alwaysTileConflictDesktopIndex(for: app) {
                        HStack(spacing: 8) {
                            Label("Desktop tiling is Off on Desktop \(conflictDesktop).", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Button("Enable Desktop \(conflictDesktop) Tiling") {
                                model.setDesktopTilingEnabled(spaceIndex: conflictDesktop, enabled: true)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
