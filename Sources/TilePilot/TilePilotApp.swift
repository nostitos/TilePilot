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

    private var missingEssentials: [SystemCheckRow] {
        model.systemCheckRows.filter { row in
            switch row.id {
            case "yabai-installed", "skhd-installed", "yabai-running", "skhd-running", "accessibility":
                return row.status != .good
            default:
                return false
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome to TilePilot")
                        .font(.title2.weight(.semibold))
                    Text("TilePilot is the control app. It needs two helper tools before it can manage windows and keyboard shortcuts on your Mac. You can install the missing pieces automatically, then recheck here.")
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
                        Text("Homebrew: just the installer TilePilot currently uses to fetch yabai and skhd. You do not need to manage Homebrew directly unless you want to.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Accessibility permission is optional, but some UI helpers work better with it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Missing or incomplete right now")
                            .font(.headline)
                        if missingEssentials.isEmpty {
                            Text("Everything essential already looks good.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(missingEssentials) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(row.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 10) {
                    Button("Install Missing Dependencies") {
                        model.runSetupInstallerInTerminal()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Open Accessibility Settings") {
                        model.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)

                    Button("Recheck") {
                        Task { await model.refreshDoctor() }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Continue") {
                        model.dismissFirstLaunchGreeting()
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }

                Text("TilePilot will still open now. The app will become fully useful as these requirements are completed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(minWidth: 620, idealWidth: 700, minHeight: 420)
        }
    }
}
