import SwiftUI

struct NowDashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedWindowID: Int?

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
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
                            if shouldShowStaleOverviewNotice(for: snapshot), let reason = snapshot.degradedReason {
                                staleOverviewNotice(reason: reason)
                            }

                            if shouldShowPreciseOverview(for: snapshot) {
                                desktopPreviewCard(snapshot, scrollProxy: scrollProxy)
                                yabaiMapCard(snapshot)
                            } else if snapshot.source == .yabai {
                                if snapshot.degraded, let reason = snapshot.degradedReason {
                                    degradedBanner(reason: reason)
                                }
                                desktopPreviewUnavailableCard
                                fallbackMapCard(snapshot)
                            } else {
                                if snapshot.degraded, let reason = snapshot.degradedReason {
                                    degradedBanner(reason: reason)
                                }
                                desktopPreviewUnavailableCard
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
                    .animation(model.overlayRefreshPolicy == .full ? .default : nil, value: model.overviewDisplayPreviews)
                    .animation(model.overlayRefreshPolicy == .full ? .default : nil, value: model.overviewDisplaySections)
                    .animation(model.overlayRefreshPolicy == .full ? .default : nil, value: model.liveStateSnapshot)
                }
                .navigationTitle("TilePilot")
                .task {
                    await model.refreshLiveState()
                    model.ensureOverviewCachesIfNeeded()
                }
                .onAppear {
                    model.ensureOverviewCachesIfNeeded()
                }
            }
        }
    }

    private var desktopPreviewUnavailableCard: some View {
        GroupBox {
            Text("Desktop mini-map unavailable in fallback/degraded mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Desktop Mini-map", systemImage: "square.grid.3x3")
        }
    }

    private var hasCachedPreciseOverview: Bool {
        !model.overviewDisplayPreviews.isEmpty || !model.overviewDisplaySections.isEmpty
    }

    private func shouldShowPreciseOverview(for snapshot: LiveStateSnapshot) -> Bool {
        if snapshot.source == .yabai && !snapshot.degraded {
            return true
        }
        return snapshot.source == .yabai && snapshot.degraded && hasCachedPreciseOverview
    }

    private func shouldShowStaleOverviewNotice(for snapshot: LiveStateSnapshot) -> Bool {
        snapshot.degraded && snapshot.source == .yabai && hasCachedPreciseOverview
    }

    private func desktopPreviewCard(_ snapshot: LiveStateSnapshot, scrollProxy: ScrollViewProxy) -> some View {
        let previews = model.overviewDisplayPreviews
        let maxDisplayArea = previews
            .map { max($0.frameW, 1) * max($0.frameH, 1) }
            .max() ?? 1
        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if previews.isEmpty {
                    Text("No preview available for current displays.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(previews) { display in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(display.name, systemImage: display.focused ? "display.and.arrow.down" : "display")
                                    .font(.caption.weight(.semibold))
                                Spacer(minLength: 0)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: previewDesktopCardMinimumWidth(for: display, maxDisplayArea: maxDisplayArea)), spacing: 8)], spacing: 8) {
                                ForEach(display.desktops) { desktop in
                                    OverviewDesktopPreviewCard(
                                        desktop: desktop,
                                        displayAspectRatio: display.aspectRatio,
                                        selectedWindowID: selectedWindowID,
                                        onDesktopSelect: { desktopIndex in
                                            model.focusDesktop(index: desktopIndex)
                                        },
                                        onDesktopTilingChange: { desktopIndex, enabled in
                                            model.setDesktopTilingEnabled(spaceIndex: desktopIndex, enabled: enabled)
                                        },
                                        onWindowActivate: { windowID, desktopIndex in
                                            selectedWindowID = windowID
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                scrollProxy.scrollTo("overview-window-\(windowID)", anchor: .center)
                                            }
                                            model.focusWindow(windowID: windowID, desktopIndex: desktopIndex)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Desktop Mini-map", systemImage: "square.grid.3x3")
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

    private func staleOverviewNotice(reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
                .font(.caption)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Live data may be temporarily out of date.")
                    .font(.caption.weight(.semibold))
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let liveStateHelp = liveStateHelp(for: reason) {
                    HStack(spacing: 8) {
                        ForEach(liveStateHelp.actions, id: \.label) { action in
                            Button(action.label, action: action.handler)
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        )
    }

    private func yabaiMapCard(_ snapshot: LiveStateSnapshot) -> some View {
        let runtimeEnabled = model.canRunYabaiRuntimeCommands
        let runtimeDisabledReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"
        let sections = model.overviewDisplaySections

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if sections.isEmpty {
                    Text("No displays returned by yabai.")
                        .foregroundStyle(.secondary)
                } else {
                    if !runtimeEnabled {
                        Text("Window controls unavailable: \(runtimeDisabledReason)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(sections) { displaySection in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(displaySection.display.name, systemImage: displaySection.display.focused ? "display.and.arrow.down" : "display")
                                    .font(.headline)
                                Spacer()
                                Text("Visible: \(displaySection.visibleWindowCount) · Total: \(displaySection.totalWindowCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if displaySection.spaces.isEmpty {
                                Text("No desktops returned for this display.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(displaySection.spaces) { spaceSection in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Button {
                                                model.focusDesktop(index: spaceSection.space.index)
                                            } label: {
                                                Text(spaceTitle(spaceSection.space))
                                                    .font(.subheadline.weight(.semibold))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Switch to Desktop \(spaceSection.space.index).")
                                            statusPill(spaceSection.tilingEnabled ? "Tiling On" : "Tiling Off", color: spaceSection.tilingEnabled ? .blue : .orange)
                                            Spacer()
                                            Text("Visible: \(spaceSection.visibleWindowCount) · Total: \(spaceSection.totalWindowCount)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        if spaceSection.totalWindowCount == 0 {
                                            Text("No windows on this desktop.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            if spaceSection.visibleWindowCount == 0 {
                                                Text("No visible windows on this desktop (Total: \(spaceSection.totalWindowCount)).")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            ForEach(spaceSection.windows) { window in
                                                windowControlRow(
                                                    window: window,
                                                    desktopTilingEnabled: spaceSection.tilingEnabled,
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
        desktopTilingEnabled: Bool?,
        runtimeEnabled: Bool,
        runtimeDisabledReason: String
    ) -> some View {
        let defaultBehavior = defaultBehaviorBadge(for: window.app, desktopTilingEnabled: desktopTilingEnabled)
        return HStack(alignment: .center, spacing: 8) {
            OverviewWindowIconControl(
                window: window,
                runtimeEnabled: runtimeEnabled,
                runtimeDisabledReason: runtimeDisabledReason
            )

            Text(window.app)
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
            }
            if desktopTilingEnabled == false {
                statusPill("Floating (Desktop tiling off)", color: .orange)
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
                if window.isRuntimeManageable {
                    statusPill(window.floating ? "Floating" : "Tiled", color: window.floating ? .orange : .green)
                } else {
                    statusPill("Limited", color: .gray)
                }
            }
            .buttonStyle(.plain)
            .disabled(!runtimeEnabled || !window.isRuntimeManageable)
            .help(
                !window.isRuntimeManageable
                ? "\(window.app) does not expose move/control hooks for this window right now."
                : (runtimeEnabled ? "Toggle floating/tiled state." : runtimeDisabledReason)
            )

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
            .disabled(!runtimeEnabled || !window.isRuntimeManageable)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
        .id("overview-window-\(window.id)")
    }

    private func defaultBehaviorBadge(for appName: String, desktopTilingEnabled: Bool?) -> (text: String, color: Color, help: String) {
        let behavior = model.appTilingBehavior(for: appName)
        let desktopNote = desktopTilingEnabled == false ? " Desktop tiling is currently off here." : ""
        switch behavior {
        case .neverTile:
            return ("Default Float", .orange, "App rule says this app should stay floating by default.\(desktopNote)")
        case .alwaysTile:
            return ("Default Tiled", .green, "App rule says this app should be auto-tiled by default.\(desktopNote)")
        case .useDefault:
            if model.windowBehaviorPolicyDraft.manualTilingModeEnabled {
                return ("Default Float", .orange, "No app-specific rule. Global default is floating because Manual Tiling Mode is enabled.\(desktopNote)")
            } else {
                return ("Default Tiled", .green, "No app-specific rule. Global default is auto-tiled.\(desktopNote)")
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

    private func previewDesktopCardMinimumWidth(for display: OverviewDisplayPreview, maxDisplayArea: Double) -> CGFloat {
        guard maxDisplayArea > 1 else { return 300 }
        let area = max(display.frameW, 1) * max(display.frameH, 1)
        let normalized = max(0.35, min(1.0, area / maxDisplayArea))
        let scale = sqrt(normalized)
        let minWidth: Double = 240
        let maxWidth: Double = 340
        return CGFloat(minWidth + (maxWidth - minWidth) * scale)
    }
}
