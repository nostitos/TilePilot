import SwiftUI

struct WindowBadgeView: View {
    @ObservedObject var model: AppModel
    let badge: WindowBadgeState
    var badgeWidth: CGFloat = 52
    var badgeHeight: CGFloat = 11

    private var runtimeEnabled: Bool { model.canRunYabaiRuntimeCommands }
    private var runtimeDisabledReason: String { model.yabaiRuntimeControlDisabledReason ?? "Window controls unavailable" }

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
            if runtimeEnabled {
                Button("Set Floating") {
                    model.setWindowFloating(windowID: badge.windowID, shouldFloat: true)
                }
                Button("Set Auto-Tiled") {
                    model.setWindowFloating(windowID: badge.windowID, shouldFloat: false)
                }
                Button("Toggle Floating/Auto-Tiled") {
                    model.toggleWindowFloating(windowID: badge.windowID)
                }
                Divider()
                Button("Focus Window") {
                    model.focusWindow(windowID: badge.windowID)
                }
                Divider()
                Button("Open Overview") {
                    model.requestOpenTilePilotTab(.now)
                }
            } else {
                Text(runtimeDisabledReason)
            }
        }
    }

    private var borderColor: Color {
        if badge.isFocused {
            return badge.isFloating ? Color.orange.opacity(0.92) : Color.blue.opacity(0.92)
        }
        return Color.white.opacity(0.36)
    }

    private var fillColor: Color {
        (badge.isFloating ? Color.orange : Color.blue).opacity(0.95)
    }

    private var helpText: String {
        let state = badge.isFloating ? "Floating" : "Auto-Tiled"
        return "\(badge.app) • \(state). Left-click toggles. Right-click for options."
    }
}
