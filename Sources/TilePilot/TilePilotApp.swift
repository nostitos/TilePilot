import AppKit
import SwiftUI

enum TilePilotTab: Hashable {
    case now
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

    private let visibleTabs: [TilePilotTab] = [
        .now,
        .windowBehavior,
        .actions,
        .appearance,
        .files,
        .howItWorks,
        .system,
    ]

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
            activeTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.requestedTilePilotTab) { newValue in
            if let newValue {
                selectedTab = newValue.canonicalVisibleTab
                model.currentVisibleTab = selectedTab
                _ = model.consumeRequestedTilePilotTab()
            }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue != .appearance {
                NSColorPanel.shared.orderOut(nil)
            }
            model.currentVisibleTab = newValue
        }
        .task {
            if !hasAppliedInitialTabSelection {
                selectedTab = (model.consumeShouldStartOnSetupTab() ? TilePilotTab.system : model.currentVisibleTab).canonicalVisibleTab
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

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleTabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.systemImage)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedTab {
        case .now:
            NowDashboardView()
        case .windowBehavior:
            WindowBehaviorDashboardView()
        case .actions, .shortcuts:
            UnifiedControlsDashboardView()
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
