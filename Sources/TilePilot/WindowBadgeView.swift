import SwiftUI

struct WindowBadgeView: View {
    @ObservedObject var model: AppModel
    let badge: WindowBadgeState
    var badgeWidth: CGFloat = 52
    var badgeHeight: CGFloat = 11

    private var runtimeEnabled: Bool { model.canRunYabaiRuntimeCommands && badge.isRuntimeManageable }
    private var runtimeDisabledReason: String {
        if !model.canRunYabaiRuntimeCommands {
            return model.yabaiRuntimeControlDisabledReason ?? "Window controls unavailable"
        }
        if !badge.isRuntimeManageable {
            return "\(badge.app) does not expose move/control hooks for this window right now."
        }
        return "Window controls unavailable"
    }

    private var pinnedFeatureRows: [FeatureControlRow] {
        model.pinnedFeatureControlRows
    }

    private var pinnedDirectionalBindings: [DirectionalShortcutBinding] {
        model.pinnedDirectionalGroupBindings.flatMap(\.bindings)
    }

    private var pinnedShortcutEntries: [ShortcutEntry] {
        model.pinnedShortcutEntries.filter { entry in
            if model.featureControlRow(forShortcutEntry: entry)?.featureID != nil {
                return false
            }
            return !(model.isScriptingAdditionDesktopShortcut(entry) && !model.canRunScriptingAdditionDesktopActions)
        }
    }

    private var hasPinnedContextActions: Bool {
        !pinnedFeatureRows.isEmpty || !pinnedDirectionalBindings.isEmpty || !pinnedShortcutEntries.isEmpty
    }

    var body: some View {
        Button {
            guard runtimeEnabled else { return }
            model.toggleWindowFloating(windowID: badge.windowID)
        } label: {
            Capsule()
                .fill(fillColor)
                .frame(width: badgeWidth, height: badgeHeight)
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: badge.isFocused ? 0.9 : 0.6)
                )
                .opacity(0.62)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .contextMenu {
            ForEach(pinnedFeatureRows, id: \.id) { row in
                if let featureID = row.featureID {
                    Button(featureMenuTitle(row)) {
                        model.runFeatureControl(featureID, source: .statusMenu)
                    }
                    .disabled(row.disabledReason != nil)
                }
            }

            ForEach(pinnedDirectionalBindings, id: \.id) { binding in
                Button(shortcutMenuTitle(binding.entry)) {
                    model.runShortcut(binding.entry)
                }
            }

            ForEach(pinnedShortcutEntries, id: \.id) { entry in
                Button(shortcutMenuTitle(entry)) {
                    model.runShortcut(entry)
                }
            }

            if hasPinnedContextActions {
                Divider()
            }

            Button("Pin More Shortcuts") {
                model.openShortcutsDashboard()
            }
        }
    }

    private var borderColor: Color {
        if !badge.isRuntimeManageable {
            return Color.gray.opacity(badge.isFocused ? 0.92 : 0.52)
        }
        if badge.isFocused {
            return badge.isFloating ? Color.orange.opacity(0.92) : Color.blue.opacity(0.92)
        }
        return Color.white.opacity(0.36)
    }

    private var fillColor: Color {
        if !badge.isRuntimeManageable {
            return Color.gray.opacity(0.8)
        }
        return (badge.isFloating ? Color.orange : Color.blue).opacity(0.95)
    }

    private var helpText: String {
        let state: String
        if !badge.isRuntimeManageable {
            state = "Limited control"
        } else {
            state = badge.isFloating ? "Floating" : "Auto-Tiled"
        }
        return "\(badge.app) • \(state). Left-click toggles. Right-click for options."
    }

    private func featureMenuTitle(_ row: FeatureControlRow) -> String {
        let symbols = row.shortcutEntry.map { model.displayShortcutComboSymbols($0) }
            ?? row.assignedCombo.map { model.displayShortcutComboSymbols(from: $0) }
            ?? row.defaultCombo.map { model.displayShortcutComboSymbols(from: $0) }
        if let symbols, !symbols.isEmpty {
            return "\(symbols)  \(row.title)"
        }
        return row.title
    }

    private func shortcutMenuTitle(_ entry: ShortcutEntry) -> String {
        let symbols = model.displayShortcutComboSymbols(entry)
        let explanation = model.shortcutExplanation(entry)
        if symbols.isEmpty {
            return explanation
        }
        return "\(symbols)  \(explanation)"
    }
}
