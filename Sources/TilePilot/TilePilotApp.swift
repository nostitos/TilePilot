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

    static let visibleTabs: [TilePilotTab] = [
        .now,
        .windowBehavior,
        .actions,
        .templates,
        .workSets,
        .appearance,
        .files,
        .howItWorks,
        .system
    ]

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
        VStack(spacing: 0) {
            tabBar
            Divider()
            selectedTabContent
        }
        .frame(minWidth: 1120, minHeight: 720)
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

    private var tabBar: some View {
        HStack {
            Picker("TilePilot Section", selection: $selectedTab) {
                ForEach(TilePilotTab.visibleTabs, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab.canonicalVisibleTab {
        case .now:
            NowDashboardView()
        case .windowBehavior:
            WindowBehaviorDashboardView()
        case .actions, .shortcuts:
            UnifiedControlsDashboardView()
        case .templates:
            TemplatesDashboardView()
        case .workSets:
            WorkSetsDashboardView()
        case .appearance:
            AppearanceDashboardView()
        case .files:
            FilesDashboardView()
        case .howItWorks:
            HowItWorksDashboardView()
        case .system, .config, .health, .setup, .logs:
            SystemDashboardView()
        }
    }
}

struct UnifiedControlsDashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ShortcutsDashboardView()
    }
}
