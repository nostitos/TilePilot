import AppKit
import SwiftUI

enum TilePilotTab: Hashable {
    case now
    case templates
    case workSets
    case appearance
    case windowBehavior
    case actions
    case shortcuts
    case howItWorks
    case system
    // legacy route-only cases (mapped to .system)
    case files
    case config
    case health
    case setup
    case logs

    var title: String {
        switch self {
        case .now:
            return "Overview"
        case .appearance:
            return "Appearance"
        case .templates:
            return "Templates"
        case .workSets:
            return "Work Sets"
        case .windowBehavior:
            return "Behaviors"
        case .actions, .shortcuts:
            return "Actions & Shortcuts"
        case .howItWorks:
            return "How It Works"
        case .system, .config, .health, .setup, .logs:
            return "System"
        case .files:
            return "Config Files"
        }
    }

    var systemImage: String {
        switch self {
        case .now:
            return "rectangle.3.group"
        case .appearance:
            return "paintbrush.pointed"
        case .templates:
            return "rectangle.3.offgrid"
        case .workSets:
            return "square.stack.3d.up"
        case .windowBehavior:
            return "hand.raised.square"
        case .actions, .shortcuts:
            return "square.grid.2x2"
        case .howItWorks:
            return "questionmark.bubble"
        case .system, .config, .health, .setup, .logs:
            return "gearshape.2"
        case .files:
            return "doc.text"
        }
    }

    var canonicalVisibleTab: TilePilotTab {
        switch self {
        case .shortcuts:
            return .actions
        case .config, .health, .setup, .logs:
            return .system
        default:
            return self
        }
    }
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
                .tabItem { Label(TilePilotTab.now.title, systemImage: TilePilotTab.now.systemImage) }
                .tag(TilePilotTab.now)

            WindowBehaviorDashboardView()
                .tabItem { Label(TilePilotTab.windowBehavior.title, systemImage: TilePilotTab.windowBehavior.systemImage) }
                .tag(TilePilotTab.windowBehavior)

            UnifiedControlsDashboardView()
                .tabItem { Label(TilePilotTab.actions.title, systemImage: TilePilotTab.actions.systemImage) }
                .tag(TilePilotTab.actions)

            TemplatesDashboardView()
                .tabItem { Label(TilePilotTab.templates.title, systemImage: TilePilotTab.templates.systemImage) }
                .tag(TilePilotTab.templates)

            WorkSetsDashboardView()
                .tabItem { Label(TilePilotTab.workSets.title, systemImage: TilePilotTab.workSets.systemImage) }
                .tag(TilePilotTab.workSets)

            AppearanceDashboardView()
                .tabItem { Label(TilePilotTab.appearance.title, systemImage: TilePilotTab.appearance.systemImage) }
                .tag(TilePilotTab.appearance)

            FilesDashboardView()
                .tabItem { Label(TilePilotTab.files.title, systemImage: TilePilotTab.files.systemImage) }
                .tag(TilePilotTab.files)

            HowItWorksDashboardView()
                .tabItem { Label(TilePilotTab.howItWorks.title, systemImage: TilePilotTab.howItWorks.systemImage) }
                .tag(TilePilotTab.howItWorks)

            SystemDashboardView()
                .tabItem { Label(TilePilotTab.system.title, systemImage: TilePilotTab.system.systemImage) }
                .tag(TilePilotTab.system)
        }
        .environment(\.controlActiveState, .key)
        .onChange(of: model.requestedTilePilotTab) { newValue in
            if let newValue {
                selectedTab = newValue.canonicalVisibleTab
                model.currentVisibleTab = selectedTab
                model.publishLatestLiveStateForCurrentTab(force: true)
                _ = model.consumeRequestedTilePilotTab()
            }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue != .appearance {
                NSColorPanel.shared.orderOut(nil)
            }
            model.currentVisibleTab = newValue
            model.publishLatestLiveStateForCurrentTab(force: true)
        }
        .task {
            if !hasAppliedInitialTabSelection {
                selectedTab = (model.consumeShouldStartOnSetupTab() ? TilePilotTab.system : model.currentVisibleTab).canonicalVisibleTab
                hasAppliedInitialTabSelection = true
            }
            model.currentVisibleTab = selectedTab
            model.publishLatestLiveStateForCurrentTab(force: true)
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
