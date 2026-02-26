import AppKit
import Combine
import SwiftUI

@MainActor
final class CoachWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = CoachRootView()
            .environmentObject(model)
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title = "TilePilot"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 980, height: 680))
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("TilePilotMainWindow")

        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let onOpenCoach: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, onOpenCoach: @escaping () -> Void) {
        self.model = model
        self.onOpenCoach = onOpenCoach
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusButton()
        bindModel()
        updateButtonAppearance()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "TilePilot"
    }

    private func bindModel() {
        model.$doctorSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButtonAppearance()
            }
            .store(in: &cancellables)

        model.$isRefreshing
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateButtonAppearance()
            }
            .store(in: &cancellables)
    }

    private func updateButtonAppearance() {
        guard let button = statusItem.button else { return }
        button.image = renderedStatusIcon()
        button.contentTintColor = nil
        button.toolTip = "TilePilot • \(model.menuBarStatusLine)"
    }

    private func renderedStatusIcon() -> NSImage? {
        let symbol = "square.grid.2x2"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "TilePilot status")?
            .withSymbolConfiguration(config) else {
            return nil
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)
        NSColor.clear.setFill()
        rect.fill()

        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.setFill()
        rect.fill(using: .sourceAtop)

        image.isTemplate = false
        return image
    }

    private func tintColor(for badge: HealthBadgeLevel?) -> NSColor {
        switch badge {
        case .healthy: return .systemGreen
        case .warning: return .systemYellow
        case .degraded: return .systemOrange
        case .blocked: return .systemRed
        case .none: return .labelColor
        }
    }

    @objc
    private func handleStatusItemClick(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) == true)
        if isRightClick {
            presentQuickMenu()
        } else {
            onOpenCoach()
        }
    }

    private func presentQuickMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Open TilePilot", action: #selector(openCoach)))
        menu.addItem(item("Open Window Behavior", action: #selector(openWindowBehaviorSettings)))
        menu.addItem(item("Show Shortcuts", action: #selector(openShortcuts)))

        menu.addItem(.separator())
        let runtimeEnabled = model.canRunYabaiRuntimeCommands
        let runtimeReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"
        let focusedAvailable = runtimeEnabled && model.focusedWindowState != nil
        let focusedReason = focusedAvailable ? "" : (model.focusedWindowState == nil ? "No focused window" : runtimeReason)
        menu.addItem(item(focusedAvailable ? "Toggle Focused Window Float/Tile" : "Toggle Focused Window Float/Tile (\(focusedReason))", action: #selector(toggleFocusedWindowTiling), enabled: focusedAvailable))
        menu.addItem(item(focusedAvailable ? "Float Focused Window" : "Float Focused Window (\(focusedReason))", action: #selector(floatFocusedWindow), enabled: focusedAvailable))
        menu.addItem(item(focusedAvailable ? "Tile Focused Window" : "Tile Focused Window (\(focusedReason))", action: #selector(tileFocusedWindow), enabled: focusedAvailable))

        menu.addItem(.separator())
        let disableHoverTitle = runtimeEnabled ? "Disable Hover Focus" : "Disable Hover Focus (\(runtimeReason))"
        let manualOnTitle = runtimeEnabled ? "Enable Manual Tiling Mode" : "Enable Manual Tiling Mode (\(runtimeReason))"
        let manualOffTitle = runtimeEnabled ? "Disable Manual Tiling Mode" : "Disable Manual Tiling Mode (\(runtimeReason))"
        menu.addItem(item(disableHoverTitle, action: #selector(disableHoverFocus), enabled: runtimeEnabled))
        menu.addItem(item(manualOnTitle, action: #selector(enableManualTilingMode), enabled: runtimeEnabled))
        menu.addItem(item(manualOffTitle, action: #selector(disableManualTilingMode), enabled: runtimeEnabled))

        let balanceItem = item("Align Tiles (Balance)", action: #selector(runQuickAction(_:)), enabled: balanceTilesQuickActionEnabled())
        balanceItem.representedObject = CoachActionID.balanceSpace.rawValue
        menu.addItem(balanceItem)

        menu.addItem(.separator())
        menu.addItem(setupDiagnosticsSubmenuItem())

        menu.addItem(.separator())
        menu.addItem(item("Quit", action: #selector(quitApp)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func item(_ title: String, action: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        return item
    }

    private func setupDiagnosticsSubmenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Setup & Diagnostics…", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(item(model.isLaunchingSetupInstaller ? "Opening Installer..." : "Install Dependencies", action: #selector(runSetupInstaller), enabled: !model.isLaunchingSetupInstaller))
        submenu.addItem(item("Check Setup", action: #selector(runDoctor), enabled: !model.isRefreshing))
        submenu.addItem(.separator())
        submenu.addItem(item("Copy Issue Summary", action: #selector(copyIssueSummary), enabled: model.doctorSnapshot != nil))
        submenu.addItem(item("Export Diagnostics", action: #selector(exportDiagnostics), enabled: model.doctorSnapshot != nil))
        submenu.addItem(.separator())
        submenu.addItem(item("Open Accessibility Settings", action: #selector(openAccessibilitySettings)))
        submenu.addItem(item("Request Accessibility Access", action: #selector(requestAccessibilityAccess)))
        submenu.addItem(item("Open Mission Control Settings", action: #selector(openMissionControlSettings)))
        submenu.addItem(item("Open System Settings", action: #selector(openSystemSettings)))
        submenu.addItem(.separator())
        submenu.addItem(item("Restart yabai (Best Effort)", action: #selector(restartYabai), enabled: !model.isRefreshing))
        submenu.addItem(item("Restart skhd (Best Effort)", action: #selector(restartSkhd), enabled: !model.isRefreshing))

        parent.submenu = submenu
        return parent
    }

    private func balanceTilesQuickActionEnabled() -> Bool {
        model.quickActionCards.first(where: { $0.id == .balanceSpace })?.enabled ?? false
    }

    @objc private func openCoach() { onOpenCoach() }

    @objc private func runDoctor() {
        model.acknowledgeInitialStatusIfNeeded()
        Task { await model.refreshDoctor() }
    }

    @objc private func disableHoverFocus() {
        model.acknowledgeInitialStatusIfNeeded()
        model.disableHoverFocus()
    }

    @objc private func enableManualTilingMode() {
        model.acknowledgeInitialStatusIfNeeded()
        model.enableManualTilingMode()
    }

    @objc private func disableManualTilingMode() {
        model.acknowledgeInitialStatusIfNeeded()
        model.disableManualTilingMode()
    }

    @objc private func tileFocusedWindow() {
        model.acknowledgeInitialStatusIfNeeded()
        model.tileFocusedWindowNow()
    }

    @objc private func floatFocusedWindow() {
        model.acknowledgeInitialStatusIfNeeded()
        model.floatFocusedWindowNow()
    }

    @objc private func toggleFocusedWindowTiling() {
        model.acknowledgeInitialStatusIfNeeded()
        model.toggleFocusedWindowTiling()
    }

    @objc private func openWindowBehaviorSettings() {
        model.acknowledgeInitialStatusIfNeeded()
        model.openWindowBehaviorSettings()
        onOpenCoach()
    }

    @objc private func openShortcuts() {
        model.acknowledgeInitialStatusIfNeeded()
        model.requestOpenCoachTab(.shortcuts)
        onOpenCoach()
    }

    @objc private func runSetupInstaller() {
        model.acknowledgeInitialStatusIfNeeded()
        model.runSetupInstallerInTerminal()
    }

    @objc private func runQuickAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = CoachActionID(rawValue: raw) else { return }
        model.acknowledgeInitialStatusIfNeeded()
        model.performCoachAction(id)
    }

    @objc private func copyIssueSummary() {
        model.acknowledgeInitialStatusIfNeeded()
        model.copyIssueReadySummary()
    }

    @objc private func exportDiagnostics() {
        model.acknowledgeInitialStatusIfNeeded()
        model.exportDiagnostics()
    }

    @objc private func openAccessibilitySettings() {
        model.acknowledgeInitialStatusIfNeeded()
        model.openAccessibilitySettings()
    }

    @objc private func requestAccessibilityAccess() {
        model.acknowledgeInitialStatusIfNeeded()
        model.requestAccessibilityAccessPrompt()
    }

    @objc private func openMissionControlSettings() {
        model.acknowledgeInitialStatusIfNeeded()
        model.openMissionControlSettings()
    }

    @objc private func openSystemSettings() {
        model.acknowledgeInitialStatusIfNeeded()
        model.openSystemSettings()
    }

    @objc private func restartYabai() {
        model.acknowledgeInitialStatusIfNeeded()
        model.restartYabaiBestEffort()
    }

    @objc private func restartSkhd() {
        model.acknowledgeInitialStatusIfNeeded()
        model.restartSkhdBestEffort()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func menuBarBadgeLevel() -> HealthBadgeLevel? {
        model.menuBarVisualBadgeLevel
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var coachWindowController: CoachWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        coachWindowController = CoachWindowController(model: model)
        statusBarController = StatusBarController(model: model) { [weak self] in
            self?.model.acknowledgeInitialStatusIfNeeded()
            self?.coachWindowController?.showAndFocus()
        }

        model.startIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coachWindowController?.showAndFocus()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { [weak self] in
            guard let self else { return }
            await self.model.refreshLiveState()
            await self.model.refreshWindowBehaviorConfig()
            await self.model.refreshBootstrapSetup()
            await self.model.refreshDoctor()
        }
    }
}
