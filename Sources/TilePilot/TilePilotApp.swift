import AppKit
import SwiftUI

enum TilePilotTab: Hashable {
    case now
    case appearance
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

    private var showSetupGuideBinding: Binding<Bool> {
        Binding(
            get: { model.setupGuidePresentationState.isPresented },
            set: { isPresented in
                if !isPresented {
                    model.dismissSetupGuide()
                }
            }
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NowDashboardView()
                .tabItem { Label("Overview", systemImage: "rectangle.3.group") }
                .tag(TilePilotTab.now)

            AppearanceDashboardView()
                .tabItem { Label("Appearance", systemImage: "paintbrush.pointed") }
                .tag(TilePilotTab.appearance)

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
        }
        .sheet(isPresented: showSetupGuideBinding) {
            SetupGuideView()
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
