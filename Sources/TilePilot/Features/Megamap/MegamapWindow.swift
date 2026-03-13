import AppKit
import SwiftUI

@MainActor
final class MegamapWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel

    private enum PersistedWindowKeys {
        static let width = "TilePilot.megamapWindow.width"
        static let height = "TilePilot.megamapWindow.height"
        static let frameAutosaveName = "TilePilotMegamapWindow"
    }

    init(model: AppModel) {
        self.model = model
        let rootView = MegamapRootView()
            .environmentObject(model)
        let hosting = NSHostingController(rootView: rootView)

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1600, height: 900)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Megamap"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.setFrame(visibleFrame, display: false)
        window.minSize = NSSize(width: 980, height: 620)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        _ = window.setFrameUsingName(PersistedWindowKeys.frameAutosaveName)
        Self.restorePersistedSize(for: window)
        window.setFrameAutosaveName(PersistedWindowKeys.frameAutosaveName)

        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        snapToVisibleFrame()
        window?.makeKeyAndOrderFront(nil)
    }

    func persistCurrentWindowSize() {
        guard let window else { return }
        let defaults = UserDefaults.standard
        defaults.set(window.frame.width, forKey: PersistedWindowKeys.width)
        defaults.set(window.frame.height, forKey: PersistedWindowKeys.height)
        window.saveFrame(usingName: PersistedWindowKeys.frameAutosaveName)
    }

    func windowWillClose(_ notification: Notification) {
        persistCurrentWindowSize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistCurrentWindowSize()
    }

    private static func restorePersistedSize(for window: NSWindow) {
        let defaults = UserDefaults.standard
        let persistedWidth = CGFloat(defaults.double(forKey: PersistedWindowKeys.width))
        let persistedHeight = CGFloat(defaults.double(forKey: PersistedWindowKeys.height))
        guard persistedWidth > 0, persistedHeight > 0 else { return }
        let minWidth = window.minSize.width
        let minHeight = window.minSize.height
        let maxFrame = NSScreen.main?.visibleFrame.size
        let maxWidth = maxFrame?.width ?? persistedWidth
        let maxHeight = maxFrame?.height ?? persistedHeight
        let width = min(max(persistedWidth, minWidth), maxWidth)
        let height = min(max(persistedHeight, minHeight), maxHeight)
        var frame = window.frame
        frame.size = NSSize(width: width, height: height)
        window.setFrame(frame, display: false)
    }

    private func snapToVisibleFrame() {
        guard let window else { return }
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        guard !visibleFrame.isEmpty else { return }
        window.setFrame(visibleFrame, display: true, animate: false)
    }
}

struct MegamapRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        MegamapDashboardView()
            .environmentObject(model)
    }
}

private struct MegamapDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.46)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .tilePilotHideMegamap, object: nil)
                    }

                content(in: proxy.size)
                    .onTapGesture { }

                statusOverlay
                controlsOverlay
            }
            .background(Color.clear)
            .ignoresSafeArea()
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .animation(nil, value: model.megamapDisplaySections)
        .animation(nil, value: model.isRefreshingMegamap)
        .animation(nil, value: model.megamapLastActionMessage)
        .animation(nil, value: model.megamapLastErrorMessage)
        .task {
            model.rebuildMegamapSections()
        }
    }

    @ViewBuilder
    private func content(in size: CGSize) -> some View {
        if model.megamapDisplaySections.isEmpty {
            emptyState
        } else {
            let fitted = fittedCompositeSize(in: size)
            VStack(spacing: 10) {
                if controlsAboveComposite {
                    inlineControls
                }
                VStack(spacing: 1) {
                    ForEach(model.megamapDisplaySections) { display in
                        MegamapDisplayRow(display: display) { desktop in
                            model.focusDesktop(index: desktop.desktopIndex)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                model.rebuildMegamapSections()
                            }
                        }
                    }
                }
                .frame(width: fitted.width, height: fitted.height)
                .clipped()

                if !controlsAboveComposite {
                    inlineControls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text(model.megamapScreenRecordingAuthorized ? "No Megamap capture yet" : "Screen Recording is off")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(model.megamapScreenRecordingAuthorized ? "Use Refresh to capture all desktops." : "Megamap is showing the synthetic fallback until macOS allows screenshots for TilePilot.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Refresh") {
                    model.refreshMegamap()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isRefreshingMegamap)

                if !model.megamapScreenRecordingAuthorized {
                    Button("Open Screen Recording Settings") {
                        model.openMegamapScreenRecordingSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func totalCompositeHeight(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return model.megamapDisplaySections.reduce(CGFloat.zero) { partial, display in
            let rowHeight = megamapDisplayHeight(for: display, width: width)
            let separator: CGFloat = partial == 0 ? 0 : 1
            return partial + separator + rowHeight
        }
    }

    private func fittedCompositeSize(in size: CGSize) -> CGSize {
        let maxWidth = max(size.width * 0.99, 0)
        let maxHeight = max(size.height * 0.99 - inlineControlsReservedHeight, 0)
        guard maxWidth > 0, maxHeight > 0 else { return .zero }

        var low: CGFloat = 0
        var high: CGFloat = maxWidth
        for _ in 0..<20 {
            let mid = (low + high) / 2
            let height = totalCompositeHeight(forWidth: mid)
            if height <= maxHeight {
                low = mid
            } else {
                high = mid
            }
        }

        let fittedWidth = max(low, 0)
        return CGSize(width: fittedWidth, height: totalCompositeHeight(forWidth: fittedWidth))
    }

    private func megamapDisplayHeight(for display: MegamapDisplaySection, width: CGFloat) -> CGFloat {
        let desktopAspect = max(display.desktops.first?.displayAspectRatio ?? 1.6, 0.1)
        if display.desktops.count == 4 {
            let singleRowHeight = width / CGFloat(2.0 * desktopAspect)
            return (singleRowHeight * 2) + 1
        }
        let rowAspect = CGFloat(Double(max(display.desktops.count, 1)) * desktopAspect)
        return width / rowAspect
    }

    private var inlineControls: some View {
        HStack(spacing: 10) {
            if !model.megamapScreenRecordingAuthorized {
                Button("Open Screen Recording Settings") {
                    model.openMegamapScreenRecordingSettings()
                }
                .buttonStyle(MegamapHudButtonStyle(prominent: false))
            }

            Button(model.isRefreshingMegamap ? "Refreshing…" : "Refresh") {
                model.refreshMegamap()
            }
            .buttonStyle(MegamapHudButtonStyle(prominent: true))
            .disabled(model.isRefreshingMegamap)
        }
    }

    private var controlsAboveComposite: Bool {
        model.megamapDisplaySections.contains { $0.desktops.count == 4 }
    }

    private var inlineControlsReservedHeight: CGFloat {
        58
    }

    private var controlsOverlay: some View {
        EmptyView()
    }

    private var statusOverlay: some View {
        VStack(spacing: 8) {
            if !model.megamapScreenRecordingAuthorized {
                MegamapHudNotice(
                    text: "Screen Recording is off. Showing the synthetic preview instead of real screenshots.",
                    foreground: .white,
                    background: Color.orange.opacity(0.88)
                )
            }

            if model.isRefreshingMegamap {
                MegamapHudNotice(
                    text: "Refreshing Megamap…",
                    foreground: .white,
                    background: Color.blue.opacity(0.88)
                )
            } else if let error = model.megamapLastErrorMessage {
                MegamapHudNotice(
                    text: error,
                    foreground: .white,
                    background: Color.red.opacity(0.88)
                )
            } else if let action = model.megamapLastActionMessage {
                MegamapHudNotice(
                    text: action,
                    foreground: .white,
                    background: Color.black.opacity(0.74)
                )
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MegamapDisplayRow: View {
    let display: MegamapDisplaySection
    let onSelect: (MegamapDesktopSection) -> Void

    var body: some View {
        Group {
            if usesTwoByTwoGrid {
                VStack(spacing: 1) {
                    ForEach(twoByTwoRows.indices, id: \.self) { rowIndex in
                        HStack(spacing: 1) {
                            ForEach(twoByTwoRows[rowIndex]) { desktop in
                                tile(for: desktop)
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 1) {
                    ForEach(display.desktops) { desktop in
                        tile(for: desktop)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(compositeAspectRatio, contentMode: .fit)
        .background(Color.black)
    }

    private func tile(for desktop: MegamapDesktopSection) -> some View {
        MegamapDesktopTile(desktop: desktop) {
            onSelect(desktop)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(max(desktop.displayAspectRatio, 0.1), contentMode: .fit)
    }

    private var usesTwoByTwoGrid: Bool {
        display.desktops.count == 4
    }

    private var twoByTwoRows: [[MegamapDesktopSection]] {
        stride(from: 0, to: display.desktops.count, by: 2).map { start in
            Array(display.desktops[start..<min(start + 2, display.desktops.count)])
        }
    }

    private var compositeAspectRatio: CGFloat {
        let desktopAspect = max(display.desktops.first?.displayAspectRatio ?? 1.6, 0.1)
        if usesTwoByTwoGrid {
            let rowHeight = 1.0 / (2.0 * desktopAspect)
            let totalHeight = (rowHeight * 2.0) + (1.0 / 1000.0)
            return CGFloat(1.0 / totalHeight)
        }
        let count = max(display.desktops.count, 1)
        return CGFloat(Double(count) * desktopAspect)
    }
}

private struct MegamapDesktopTile: View {
    @EnvironmentObject private var model: AppModel
    let desktop: MegamapDesktopSection
    let onSelect: () -> Void

    var body: some View {
        Group {
            switch desktop.contentMode {
            case .screenshot:
                if let preview = desktop.fallbackPreview {
                    tileChrome {
                        MegamapMergedDesktopCanvas(
                            desktop: desktop,
                            preview: preview,
                            onDesktopSelect: onSelect,
                            onWindowSelect: { window in
                                model.focusWindow(windowID: window.id, desktopIndex: window.desktopIndex)
                            }
                        )
                    }
                } else {
                    desktopButtonTile
                }
            case .syntheticFallback:
                if let preview = desktop.fallbackPreview {
                    tileChrome {
                        MegamapSyntheticDesktopCanvas(
                            preview: preview,
                            onDesktopSelect: onSelect,
                            onWindowSelect: { window in
                                model.focusWindow(windowID: window.id, desktopIndex: window.desktopIndex)
                            }
                        )
                    }
                } else {
                    desktopButtonTile
                }
            case .unavailable:
                desktopButtonTile
            }
        }
    }

    private var overlayMessage: String? {
        if desktop.contentMode != .screenshot {
            return "#\(desktop.desktopIndex)"
        }
        return nil
    }

    private var unavailablePlaceholder: some View {
        ZStack {
            Color(white: 0.9)
            Image(systemName: "rectangle.slash")
                .font(.title2)
                .foregroundStyle(.black.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var desktopButtonTile: some View {
        Button(action: onSelect) {
            tileChrome {
                switch desktop.contentMode {
                case .screenshot:
                    if let image = desktop.screenshotPath.flatMap(NSImage.init(contentsOfFile:)) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        unavailablePlaceholder
                    }
                case .syntheticFallback:
                    unavailablePlaceholder
                case .unavailable:
                    unavailablePlaceholder
                }
            }
        }
        .buttonStyle(.plain)
        .help("Switch to Desktop #\(desktop.desktopIndex).")
    }

    private func tileChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            Color(white: 0.96)
            content()

            if desktop.focused {
                Rectangle()
                    .fill(Color.blue)
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let message = overlayMessage {
                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct MegamapSyntheticDesktopCanvas: View {
    @EnvironmentObject private var model: AppModel
    let preview: OverviewDesktopPreview
    let onDesktopSelect: () -> Void
    let onWindowSelect: (OverviewWindowPreview) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color(white: 0.96)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDesktopSelect)

                ForEach(preview.windows) { window in
                    let frame = OverviewMiniMapGeometry.frame(for: window, in: size)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            Rectangle()
                                .stroke(borderColor(for: window), lineWidth: window.focused ? 2 : 1.2)
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }

                ForEach(preview.windows) { window in
                    let frame = OverviewMiniMapGeometry.frame(for: window, in: size)
                    let iconSize = wireframeIconDimension(for: frame.size)
                    let iconFrame = OverviewMiniMapGeometry.iconFrame(for: window, iconSize: iconSize, inset: 4, in: size)
                    let runtimeEnabled = model.canRunYabaiRuntimeCommands
                    let runtimeDisabledReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"
                    let hoverTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : window.title
                    Button {
                        onWindowSelect(window)
                    } label: {
                        Group {
                            if let icon = AppIconResolver.shared.icon(forAppNamed: window.app, size: iconSize) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                            } else {
                                Image(systemName: "app")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: iconFrame.width, height: iconFrame.height)
                    }
                    .buttonStyle(.plain)
                    .help(hoverTitle)
                    .offset(x: iconFrame.minX, y: iconFrame.minY)
                    .contextMenu {
                        Button("Focus Window") {
                            model.focusWindow(windowID: window.id, desktopIndex: window.desktopIndex)
                        }
                        .disabled(!runtimeEnabled)

                        Divider()

                        Button(window.floating ? "Set Tiled" : "Set Floating") {
                            model.toggleWindowFloating(windowID: window.id)
                        }
                        .disabled(!runtimeEnabled || !window.runtimeManageable)

                        Button("Set Floating") {
                            model.setWindowFloating(windowID: window.id, shouldFloat: true)
                        }
                        .disabled(!runtimeEnabled || !window.runtimeManageable || window.floating)

                        Button("Set Tiled") {
                            model.setWindowFloating(windowID: window.id, shouldFloat: false)
                        }
                        .disabled(!runtimeEnabled || !window.runtimeManageable || !window.floating)

                        if !runtimeEnabled {
                            Divider()
                            Text("Unavailable: \(runtimeDisabledReason)")
                        } else if !window.runtimeManageable {
                            Divider()
                            Text("Limited: this window cannot be floated/tiled right now.")
                        }
                    }
                }
            }
        }
        .clipped()
    }

    private func borderColor(for window: OverviewWindowPreview) -> Color {
        if !window.runtimeManageable { return .gray }
        return window.floating ? .orange : .blue
    }

    private func wireframeIconDimension(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) * 0.72 * 1.5
        return max(18, min(40, base))
    }
}

private struct MegamapMergedDesktopCanvas: View {
    @EnvironmentObject private var model: AppModel

    let desktop: MegamapDesktopSection
    let preview: OverviewDesktopPreview
    let onDesktopSelect: () -> Void
    let onWindowSelect: (OverviewWindowPreview) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                desktopBackground
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDesktopSelect)

                ForEach(preview.windows) { window in
                    let frame = MegamapOverlayGeometry.frame(for: window, desktop: desktop, in: size)
                    Rectangle()
                        .fill(Color.black.opacity(0.05))
                        .overlay(
                            Rectangle()
                                .stroke(borderColor(for: window), lineWidth: window.focused ? 2 : 1.2)
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }

                ForEach(preview.windows) { window in
                    let frame = MegamapOverlayGeometry.frame(for: window, desktop: desktop, in: size)
                    let iconSize = wireframeIconDimension(for: frame.size)
                    let iconFrame = MegamapOverlayGeometry.iconFrame(for: window, desktop: desktop, iconSize: iconSize, inset: 4, in: size)
                    let runtimeEnabled = model.canRunYabaiRuntimeCommands
                    let runtimeDisabledReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"
                    let hoverTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : window.title
                    Button {
                        onWindowSelect(window)
                    } label: {
                        Group {
                            if let icon = AppIconResolver.shared.icon(forAppNamed: window.app, size: iconSize) {
                                Image(nsImage: icon)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                            } else {
                                Image(systemName: "app")
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: iconFrame.width, height: iconFrame.height)
                        .opacity(window.visible ? 1 : 0.75)
                    }
                    .buttonStyle(.plain)
                    .help(hoverTitle)
                    .offset(x: iconFrame.minX, y: iconFrame.minY)
                    .contextMenu {
                        Button("Focus Window") {
                            model.focusWindow(windowID: window.id, desktopIndex: window.desktopIndex)
                        }
                        .disabled(!runtimeEnabled)

                        Divider()

                        Button(window.floating ? "Set Tiled" : "Set Floating") {
                            model.toggleWindowFloating(windowID: window.id)
                        }
                        .disabled(!runtimeEnabled || !window.runtimeManageable)

                        Button("Set Floating") {
                            model.setWindowFloating(windowID: window.id, shouldFloat: true)
                        }
                        .disabled(!runtimeEnabled || !window.runtimeManageable || window.floating)

                        Button("Set Tiled") {
                            model.setWindowFloating(windowID: window.id, shouldFloat: false)
                        }
                        .disabled(!runtimeEnabled || !window.runtimeManageable || !window.floating)

                        if !runtimeEnabled {
                            Divider()
                            Text("Unavailable: \(runtimeDisabledReason)")
                        } else if !window.runtimeManageable {
                            Divider()
                            Text("Limited: this window cannot be floated/tiled right now.")
                        }
                    }
                }
            }
        }
        .clipped()
    }

    @ViewBuilder
    private var desktopBackground: some View {
        if let path = desktop.screenshotPath,
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Color(white: 0.96)
        }
    }

    private func borderColor(for window: OverviewWindowPreview) -> Color {
        if !window.runtimeManageable { return .gray }
        return window.floating ? .orange : .blue
    }

    private func wireframeIconDimension(for size: CGSize) -> CGFloat {
        let base = min(size.width, size.height) * 0.72 * 1.5
        return max(18, min(40, base))
    }
}

private enum MegamapOverlayGeometry {
    static func frame(for window: OverviewWindowPreview, desktop: MegamapDesktopSection, in canvasSize: CGSize) -> CGRect {
        let displayFrame = CGRect(
            x: desktop.displayFrameX,
            y: desktop.displayFrameY,
            width: max(desktop.displayFrameW, 1),
            height: max(desktop.displayFrameH, 1)
        )
        let cropFrame = CGRect(
            x: desktop.screenshotCropX,
            y: desktop.screenshotCropY,
            width: max(desktop.screenshotCropW, 1),
            height: max(desktop.screenshotCropH, 1)
        )

        let absoluteX = displayFrame.minX + (window.normalizedX * displayFrame.width)
        let absoluteY = displayFrame.minY + (window.normalizedY * displayFrame.height)
        let absoluteW = window.normalizedW * displayFrame.width
        let absoluteH = window.normalizedH * displayFrame.height

        let croppedX = (absoluteX - cropFrame.minX) / cropFrame.width
        let croppedY = (absoluteY - cropFrame.minY) / cropFrame.height
        let croppedW = absoluteW / cropFrame.width
        let croppedH = absoluteH / cropFrame.height

        let x = max(0, min(1, croppedX)) * canvasSize.width
        let y = max(0, min(1, croppedY)) * canvasSize.height
        let maxWidth = max(0, canvasSize.width - x)
        let maxHeight = max(0, canvasSize.height - y)
        let width = min(maxWidth, max(10, croppedW * canvasSize.width))
        let height = min(maxHeight, max(8, croppedH * canvasSize.height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func iconFrame(
        for window: OverviewWindowPreview,
        desktop: MegamapDesktopSection,
        iconSize: CGFloat,
        inset: CGFloat,
        in canvasSize: CGSize
    ) -> CGRect {
        let windowFrame = frame(for: window, desktop: desktop, in: canvasSize)
        let availableWidth = max(0, windowFrame.width - (inset * 2))
        let availableHeight = max(0, windowFrame.height - (inset * 2))
        let width = min(iconSize, availableWidth)
        let height = min(iconSize, availableHeight)
        return CGRect(
            x: windowFrame.minX + inset,
            y: windowFrame.minY + inset,
            width: width,
            height: height
        )
    }
}

private struct MegamapHudNotice: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}

private struct MegamapHudButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(background(configuration: configuration), in: RoundedRectangle(cornerRadius: 10))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private func background(configuration: Configuration) -> some ShapeStyle {
        if prominent {
            return AnyShapeStyle(Color.blue.opacity(configuration.isPressed ? 0.82 : 0.92))
        }
        return AnyShapeStyle(Color.black.opacity(configuration.isPressed ? 0.68 : 0.78))
    }
}
