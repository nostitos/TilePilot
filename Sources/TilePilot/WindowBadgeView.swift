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

    private var pinnedContextItems: [PinnedShortcutContextItem] {
        model.pinnedShortcutContextItems
    }

    private var hasPinnedContextActions: Bool {
        !pinnedContextItems.isEmpty
    }

    private var openTilePilotRow: FeatureControlRow? {
        model.featureControlRow(forID: FeatureControlID(rawValue: "app.open-tilepilot"))
    }

    private var openMegamapRow: FeatureControlRow? {
        model.featureControlRow(forID: FeatureControlID(rawValue: "app.open-megamap"))
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
            ForEach(pinnedContextItems, id: \.id) { item in
                switch item {
                case .feature(let row):
                    if let featureID = row.featureID {
                        let title = featureMenuTitle(row)
                        if featureID.rawValue == "app.keep-on-top-when-floating" {
                            Toggle(isOn: Binding(
                                get: {
                                    model.appForegroundPolicy(for: badge.app) == .keepFrontWhenFloating
                                },
                                set: { enabled in
                                    model.setAppForegroundPolicy(enabled ? .keepFrontWhenFloating : .useDefault, for: badge.app)
                                }
                            )) {
                                Text(title)
                            }
                            .disabled(row.disabledReason != nil)
                        } else {
                            Button(title) {
                                model.runFeatureControl(featureID, source: .statusMenu, appContext: badge.app)
                            }
                            .disabled(row.disabledReason != nil)
                        }
                    }
                case .directional(_, let bindings):
                    ForEach(bindings, id: \.id) { binding in
                        let title = shortcutMenuTitle(binding.entry)
                        Button(title) {
                            model.runShortcut(binding.entry)
                        }
                    }
                case .shortcut(let entry):
                    let title = shortcutMenuTitle(entry)
                    Button(title) {
                        model.runShortcut(entry)
                    }
                }
            }

            if hasPinnedContextActions {
                Divider()
            }

            if let row = openTilePilotRow {
                Button(featureMenuTitle(row)) {
                    model.openTilePilotDashboard()
                }
            } else {
                Button("Open TilePilot") {
                    model.openTilePilotDashboard()
                }
            }

            if let row = openMegamapRow {
                Button(featureMenuTitle(row)) {
                    model.presentMegamap()
                }
            } else {
                Button("Open Megamap") {
                    model.presentMegamap()
                }
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
        return menuTitle(left: row.title, rightShortcut: spacedSymbols(symbols))
    }

    private func shortcutMenuTitle(_ entry: ShortcutEntry) -> String {
        let symbols = model.displayShortcutComboSymbols(entry)
        let combo = symbols.isEmpty ? model.displayShortcutComboWords(entry) : symbols
        return menuTitle(left: model.shortcutTitle(entry), rightShortcut: spacedSymbols(combo))
    }

    private func menuTitle(left: String, rightShortcut: String?) -> String {
        let trimmedRight = rightShortcut?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedRight.isEmpty else { return left }
        return "\(left)\t\(trimmedRight)"
    }

    private func spacedSymbols(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.map(String.init).joined(separator: " ")
    }
}
