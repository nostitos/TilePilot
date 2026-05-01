import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RecentWindowTilerPickerView: View {
    @ObservedObject var model: AppModel

    private let rowHeight: CGFloat = 52
    @State private var draggedWindowID: Int?

    var body: some View {
        Group {
            if let state = model.recentWindowTilerState {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    Picker("", selection: Binding(
                        get: { state.mode },
                        set: { model.setRecentWindowTilerMode($0) }
                    )) {
                        ForEach(RecentWindowTilerMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    RecentWindowTilerGridPreview(
                        candidates: state.orderedEffectiveSelectedCandidates,
                        displayAspectRatio: state.displayAspectRatio,
                        draggedWindowID: $draggedWindowID,
                        model: model
                    )

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(state.candidates.enumerated()), id: \.element.windowID) { index, candidate in
                                RecentWindowTilerCandidateRow(
                                    order: index + 1,
                                    candidate: candidate,
                                    mode: state.mode,
                                    isSelected: state.effectiveSelectedWindowIDs.contains(candidate.windowID),
                                    isEnabled: candidate.isSelectable(in: state.mode)
                                ) {
                                    model.toggleRecentWindowTilerSelection(windowID: candidate.windowID)
                                }
                                .onDrag {
                                    draggedWindowID = candidate.windowID
                                    return NSItemProvider(object: "\(candidate.windowID)" as NSString)
                                }
                                .onDrop(
                                    of: [UTType.utf8PlainText.identifier, UTType.plainText.identifier],
                                    delegate: RecentWindowTilerCandidateDropDelegate(
                                        targetWindowID: candidate.windowID,
                                        draggedWindowID: $draggedWindowID,
                                        model: model
                                    )
                                )
                            }
                        }
                        .padding(.vertical, 1)
                    }
                    .frame(height: listHeight(for: state.candidates.count))

                    HStack {
                        Text("\(state.selectedCount) selected")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(state.selectedCount == 0 ? .red : .secondary)

                        Spacer()

                        Button("Cancel") {
                            model.dismissRecentWindowTiler()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("Tile Selected Windows") {
                            model.applyRecentWindowTilerSelection()
                        }
                        .buttonStyle(RecentWindowTilerPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(state.selectedCount == 0)
                    }
                }
                .padding(16)
                .frame(width: 500)
            } else {
                EmptyView()
                    .frame(width: 500, height: 120)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick Windows to Tile")
                .font(.title3.weight(.semibold))
            Text("Click to select. Drag rows to change placement order.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func listHeight(for count: Int) -> CGFloat {
        CGFloat(min(max(count, 1), 8)) * rowHeight + CGFloat(max(0, min(count, 8) - 1) * 6)
    }
}

private struct RecentWindowTilerGridPreview: View {
    let candidates: [RecentWindowTilerCandidate]
    let displayAspectRatio: Double
    @Binding var draggedWindowID: Int?
    let model: AppModel

    private var grid: (rows: Int, cols: Int) {
        RecentWindowGridPlanner.dimensions(
            windowCount: candidates.count,
            displayAspectRatio: displayAspectRatio
        )
    }

    private var placements: [RecentWindowGridPlacement] {
        RecentWindowGridPlanner.placements(
            windowCount: candidates.count,
            rows: grid.rows,
            cols: grid.cols
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Result Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Drag tiles to reorder")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !candidates.isEmpty {
                    Text("\(grid.rows) x \(grid.cols)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { proxy in
                let canvas = previewCanvasSize(in: proxy.size)
                let origin = CGPoint(
                    x: (proxy.size.width - canvas.width) / 2,
                    y: (proxy.size.height - canvas.height) / 2
                )

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                        .frame(width: canvas.width, height: canvas.height)
                        .position(x: origin.x + (canvas.width / 2), y: origin.y + (canvas.height / 2))

                    ForEach(0..<(grid.rows * grid.cols), id: \.self) { index in
                        let row = index / max(grid.cols, 1)
                        let col = index % max(grid.cols, 1)
                        let rect = cellRect(row: row, col: col, rowSpan: 1, colSpan: 1, canvas: canvas)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            .frame(width: rect.width, height: rect.height)
                            .position(x: origin.x + rect.midX, y: origin.y + rect.midY)
                    }

                    ForEach(Array(candidates.enumerated()), id: \.element.windowID) { index, candidate in
                        if placements.indices.contains(index) {
                            let placement = placements[index]
                            let rect = cellRect(
                                row: placement.row,
                                col: placement.col,
                                rowSpan: placement.rowSpan,
                                colSpan: placement.colSpan,
                                canvas: canvas
                            )
                            let iconSize = min(44, max(30, min(rect.width, rect.height) * 0.66))

                            RecentWindowTilerGridPreviewTile(candidate: candidate, order: index + 1, iconSize: iconSize)
                                .frame(width: rect.width, height: rect.height)
                                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .position(x: origin.x + rect.midX, y: origin.y + rect.midY)
                                .zIndex(Double(index + 1))
                                .gesture(
                                    DragGesture(minimumDistance: 3, coordinateSpace: .named("RecentWindowTilerPreview"))
                                        .onChanged { value in
                                            let activeWindowID = draggedWindowID ?? candidate.windowID
                                            draggedWindowID = activeWindowID

                                            guard let targetWindowID = previewTargetWindowID(
                                                at: value.location,
                                                canvas: canvas,
                                                origin: origin
                                            ),
                                                targetWindowID != activeWindowID else {
                                                return
                                            }

                                            model.reorderRecentWindowTilerCandidate(
                                                draggedWindowID: activeWindowID,
                                                targetWindowID: targetWindowID
                                            )
                                        }
                                        .onEnded { _ in
                                            draggedWindowID = nil
                                        }
                                )
                        }
                    }
                }
                .coordinateSpace(name: "RecentWindowTilerPreview")
            }
            .frame(height: 156)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func previewCanvasSize(in size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let aspectRatio = max(displayAspectRatio, 0.5)
        let widthFromHeight = size.height * aspectRatio
        if widthFromHeight <= size.width {
            return CGSize(width: widthFromHeight, height: size.height)
        }
        return CGSize(width: size.width, height: size.width / aspectRatio)
    }

    private func cellRect(
        row: Int,
        col: Int,
        rowSpan: Int,
        colSpan: Int,
        canvas: CGSize
    ) -> CGRect {
        let gap: CGFloat = 5
        let cols = CGFloat(max(grid.cols, 1))
        let rows = CGFloat(max(grid.rows, 1))
        let cellWidth = (canvas.width - ((cols - 1) * gap)) / cols
        let cellHeight = (canvas.height - ((rows - 1) * gap)) / rows
        return CGRect(
            x: CGFloat(col) * (cellWidth + gap),
            y: CGFloat(row) * (cellHeight + gap),
            width: (cellWidth * CGFloat(max(colSpan, 1))) + (gap * CGFloat(max(colSpan - 1, 0))),
            height: (cellHeight * CGFloat(max(rowSpan, 1))) + (gap * CGFloat(max(rowSpan - 1, 0)))
        )
    }

    private func previewTargetWindowID(at point: CGPoint, canvas: CGSize, origin: CGPoint) -> Int? {
        for (index, candidate) in candidates.enumerated().reversed() {
            guard placements.indices.contains(index) else { continue }
            let placement = placements[index]
            let rect = cellRect(
                row: placement.row,
                col: placement.col,
                rowSpan: placement.rowSpan,
                colSpan: placement.colSpan,
                canvas: canvas
            ).offsetBy(dx: origin.x, dy: origin.y)
            if rect.contains(point) {
                return candidate.windowID
            }
        }
        return nil
    }
}

private struct RecentWindowTilerGridPreviewTile: View {
    let candidate: RecentWindowTilerCandidate
    let order: Int
    let iconSize: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.blue.opacity(0.15))

            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.blue.opacity(0.72), lineWidth: 1.5)

            if let icon = AppIconResolver.shared.icon(forAppNamed: candidate.app, size: iconSize) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .help(candidate.primaryDisplayText)
            }

            Text("\(order)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue, in: Circle())
                .padding(5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(candidate.secondaryDisplayText.map { "\(candidate.primaryDisplayText) - \($0)" } ?? candidate.primaryDisplayText)
    }
}

private struct RecentWindowTilerCandidateDropDelegate: DropDelegate {
    let targetWindowID: Int
    @Binding var draggedWindowID: Int?
    let model: AppModel

    func dropEntered(info: DropInfo) {
        guard let draggedWindowID, draggedWindowID != targetWindowID else { return }
        model.reorderRecentWindowTilerCandidate(
            draggedWindowID: draggedWindowID,
            targetWindowID: targetWindowID
        )
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedWindowID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct RecentWindowTilerPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? Color.blue : Color.secondary.opacity(0.35))
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct RecentWindowTilerCandidateRow: View {
    let order: Int
    let candidate: RecentWindowTilerCandidate
    let mode: RecentWindowTilerMode
    let isSelected: Bool
    let isEnabled: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            onToggle()
        }) {
            HStack(spacing: 10) {
                Text("\(order)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .frame(width: 24, height: 24)
                    .background(isSelected ? Color.blue : Color.secondary.opacity(0.13), in: Circle())

                Image(nsImage: appIcon(pid: candidate.pid))
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(candidate.primaryDisplayText)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if candidate.focused {
                            chip("Focused", tint: .blue)
                        }
                        if candidate.isAXOnly {
                            chip("AX-only", tint: .teal)
                        }
                        chip(candidate.floating ? "Floating" : "Tiled", tint: candidate.floating ? .orange : .green)
                    }
                    if let secondaryText = candidate.secondaryDisplayText {
                        Text(secondaryText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checkColor)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(rowBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.blue.opacity(0.55) : Color.secondary.opacity(0.16), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? 1 : 0.56)
        }
        .buttonStyle(.plain)
        .help(candidate.disabledReason(in: mode) ?? rowHelpText)
    }

    private var rowHelpText: String {
        candidate.secondaryDisplayText.map { "\(candidate.primaryDisplayText) - \($0)" } ?? candidate.primaryDisplayText
    }

    private var rowBackground: some ShapeStyle {
        isSelected ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08)
    }

    private var checkColor: Color {
        if !isEnabled { return Color.secondary.opacity(0.35) }
        return isSelected ? Color.blue : Color.secondary.opacity(0.55)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    private func appIcon(pid: Int) -> NSImage {
        if let icon = NSRunningApplication(processIdentifier: pid_t(pid))?.icon {
            return icon
        }
        return NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "App") ?? NSImage(size: NSSize(width: 28, height: 28))
    }
}
