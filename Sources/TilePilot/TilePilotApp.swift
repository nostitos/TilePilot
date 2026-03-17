import AppKit
import SwiftUI

enum TilePilotTab: Hashable {
    case now
    case windowBehavior
    case actions
    case shortcuts
    case system
    // legacy route-only cases (mapped to .system)
    case files
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

struct TilePilotRootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: TilePilotTab = .now
    @State private var hasAppliedInitialTabSelection = false
    @State private var showFirstLaunchGreeting = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NowDashboardView()
                .tabItem { Label("Overview", systemImage: "rectangle.3.group") }
                .tag(TilePilotTab.now)

            WindowBehaviorDashboardView()
                .tabItem { Label("Behaviors", systemImage: "hand.raised.square") }
                .tag(TilePilotTab.windowBehavior)

            UnifiedControlsDashboardView()
                .tabItem { Label("Actions & Shortcuts", systemImage: "square.grid.2x2") }
                .tag(TilePilotTab.actions)

            FilesDashboardView()
                .tabItem { Label("Config Files", systemImage: "doc.text") }
                .tag(TilePilotTab.files)

            SystemDashboardView()
                .tabItem { Label("System", systemImage: "gearshape.2") }
                .tag(TilePilotTab.system)
        }
        .onChange(of: model.requestedTilePilotTab) { newValue in
            if let newValue {
                switch newValue {
                case .actions, .shortcuts:
                    selectedTab = .actions
                case .files:
                    selectedTab = .files
                case .config, .health, .setup, .logs:
                    selectedTab = .system
                default:
                    selectedTab = newValue
                }
                model.currentVisibleTab = selectedTab
                _ = model.consumeRequestedTilePilotTab()
            }
        }
        .onChange(of: selectedTab) { newValue in
            model.currentVisibleTab = newValue
        }
        .task {
            if !hasAppliedInitialTabSelection {
                selectedTab = model.consumeShouldStartOnSetupTab() ? .system : .now
                hasAppliedInitialTabSelection = true
            }
            model.currentVisibleTab = selectedTab
            model.startIfNeeded()
            if model.doctorSnapshot == nil {
                await model.refreshDoctor()
            }
            showFirstLaunchGreeting = model.shouldShowFirstLaunchGreeting
        }
        .onReceive(model.$doctorSnapshot) { _ in
            if model.shouldShowFirstLaunchGreeting {
                showFirstLaunchGreeting = true
            }
        }
        .onReceive(model.$bootstrapSnapshot) { _ in
            if model.shouldShowFirstLaunchGreeting {
                showFirstLaunchGreeting = true
            }
        }
        .sheet(isPresented: $showFirstLaunchGreeting, onDismiss: {
            model.dismissFirstLaunchGreeting()
        }) {
            FirstLaunchGreetingView(isPresented: $showFirstLaunchGreeting)
                .environmentObject(model)
        }
    }
}

struct UnifiedControlsDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ShortcutsDashboardView()
    }
}

private struct FirstLaunchGreetingView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    private var requiredMissingItems: [SystemCheckRow] {
        model.setupBlockingRows
    }

    private var missingStatusSummary: String {
        model.primarySetupAction.summaryTitle
    }

    private var missingStatusColor: Color {
        if model.primarySetupAction == .ready {
            return .green
        }
        if requiredMissingItems.contains(where: { $0.status == .error }) {
            return .red
        }
        if requiredMissingItems.contains(where: { $0.status == .warning }) {
            return .orange
        }
        if requiredMissingItems.contains(where: { $0.status == .notice }) || model.primarySetupAction == .recheck {
            return .yellow
        }
        return .green
    }

    private var missingStatusSymbol: String {
        if model.primarySetupAction == .ready {
            return "checkmark.circle.fill"
        }
        if requiredMissingItems.contains(where: { $0.status == .error }) {
            return "xmark.circle.fill"
        }
        if requiredMissingItems.contains(where: { $0.status == .warning }) {
            return "exclamationmark.triangle.fill"
        }
        if requiredMissingItems.contains(where: { $0.status == .notice }) || model.primarySetupAction == .recheck {
            return "questionmark.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private func color(for status: SystemCheckStatus) -> Color {
        switch status {
        case .good: return .green
        case .notice: return .yellow
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to TilePilot")
                        .font(.title2.weight(.semibold))
                    Text("TilePilot needs two helper tools to manage windows and keyboard shortcuts on your Mac. TilePilot can install them and recheck setup automatically.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How this works")
                            .font(.headline)
                        Text("TilePilot: the app you use to see windows, change behavior, and run actions.")
                            .font(.subheadline)
                        Text("yabai: the window manager that actually tiles, moves, and focuses windows and desktops.")
                            .font(.subheadline)
                        Text("skhd: the background shortcut helper that listens for global hotkeys.")
                            .font(.subheadline)
                        Text("Accessibility permission is optional. Core TilePilot setup does not depend on it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: missingStatusSymbol)
                                .foregroundStyle(missingStatusColor)
                                .font(.title3.weight(.semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Setup status")
                                    .font(.headline)
                                Text(missingStatusSummary)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(missingStatusColor)
                            }
                        }
                        Text(model.primarySetupActionDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if requiredMissingItems.isEmpty {
                            Text("Everything essential already looks good.")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        } else {
                            ForEach(requiredMissingItems) { row in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: row.status.symbolName)
                                        .foregroundStyle(color(for: row.status))
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(row.detail)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        if !model.setupOptionalRowsNeedingAttention.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Optional guidance")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(model.setupOptionalRowsNeedingAttention) { row in
                                    Text("\(row.title): \(row.detail)")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    if model.primarySetupAction == .ready {
                        Button("Continue") {
                            model.dismissFirstLaunchGreeting()
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isPrimarySetupActionInFlight)
                    } else {
                        Button(model.primarySetupActionLabel) {
                            model.performPrimarySetupAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isPrimarySetupActionInFlight)
                    }

                    Button("Recheck Setup") {
                        model.performSetupAction(.recheck)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Continue") {
                        model.dismissFirstLaunchGreeting()
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }

                Text("TilePilot will still open now. Setup will recheck automatically after helper install or settings changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(minWidth: 620, idealWidth: 700, minHeight: 420)
        }
    }
}
