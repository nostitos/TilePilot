import SwiftUI

struct HowItWorksDashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introCard
                    windowBehaviorSection
                    shortcutsSection
                }
                .padding()
            }
            .navigationTitle("How It Works")
        }
    }

    private var introCard: some View {
        GroupBox {
            Text("Use this tab for quick visual explanations. The settings tabs stay focused on changing behavior.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Overview", systemImage: "lightbulb")
        }
    }

    private var windowBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Window Behavior")
            conceptCard(
                title: "Desktop Auto-Tiling",
                summary: "Each desktop can either keep windows tiled or leave them floating."
            ) {
                DesktopAutoTilingExplainerDiagram()
            }
            conceptCard(
                title: "App Rules",
                summary: "App rules override the global default for specific apps."
            ) {
                AppRulesExplainerDiagram()
            }
            conceptCard(
                title: "Focus and Cursor",
                summary: "Hover Focus changes focus on pointer movement. Cursor Follows Focus moves the pointer to the focused window."
            ) {
                HoverFocusExplainerDiagram()
            }
        }
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Actions and Shortcuts")
            conceptCard(
                title: "Right-Click Menu",
                summary: "Pin high-frequency actions so they appear when you right-click the TilePilot menu bar icon."
            ) {
                RightClickMenuExplainerDiagram()
            }
            conceptCard(
                title: "Layout Outcomes",
                summary: "Some layout actions leave windows floating. Others finish with windows tiled."
            ) {
                LayoutOutcomeExplainerDiagram()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func conceptCard<Content: View>(
        title: String,
        summary: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }
}
