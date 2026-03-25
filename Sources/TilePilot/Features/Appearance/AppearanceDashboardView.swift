import SwiftUI

struct AppearanceDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    overlaysCard
                    spacingCard
                }
                .padding()
            }
            .navigationTitle("TilePilot")
            .task { await model.refreshWindowBehaviorConfig() }
        }
    }

    private var overlaysCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("These controls affect TilePilot's desktop overlays only. MegaMap and mini-map wireframes are unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Window Badges", isOn: Binding(
                    get: { model.showWindowBadgeOverlay },
                    set: { model.setWindowBadgeOverlayEnabled($0) }
                ))

                Toggle("Window Outline Overlay", isOn: Binding(
                    get: { model.showWindowOutlineOverlay },
                    set: { model.setWindowOutlineOverlayEnabled($0) }
                ))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Outline Width")
                        Spacer()
                        Text("\(Int(model.windowOutlineOverlayBaseWidth.rounded())) px")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { model.windowOutlineOverlayBaseWidth },
                            set: { model.setWindowOutlineOverlayBaseWidth($0) }
                        ),
                        in: 1.0 ... 6.0,
                        step: 1.0
                    )
                    .disabled(!model.showWindowOutlineOverlay)

                    Text("Controls the desktop Window Outline Overlay thickness in physical pixels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Overlays", systemImage: "square.stack.3d.up")
        }
    }

    private var spacingCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Global yabai tiling layout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                AppearanceIntegerControl(
                    title: "Screen Edge Padding",
                    unit: "pt",
                    value: Binding(
                        get: { model.windowBehaviorPolicyDraft.outerPadding },
                        set: { model.updateOuterPaddingDraft($0) }
                    )
                )

                AppearanceIntegerControl(
                    title: "Gap Between Tiled Windows",
                    unit: "pt",
                    value: Binding(
                        get: { model.windowBehaviorPolicyDraft.windowGap },
                        set: { model.updateWindowGapDraft($0) }
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Tiling Layout", systemImage: "rectangle.split.3x1")
        }
    }
}

private struct AppearanceIntegerControl: View {
    let title: String
    let unit: String
    @Binding var value: Int

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 100
        return formatter
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)

            TextField("0", value: $value, formatter: Self.formatter)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)

            Text(unit)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Stepper("", value: $value, in: 0 ... 100)
                .labelsHidden()
                .controlSize(.small)

            Spacer(minLength: 0)
        }
    }
}
