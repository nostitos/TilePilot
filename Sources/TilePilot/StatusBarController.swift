import AppKit
import Combine
import SwiftUI

@MainActor
final class TilePilotWindowController: NSWindowController {
    init(model: AppModel) {
        let rootView = TilePilotRootView()
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
    private let onOpenTilePilot: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, onOpenTilePilot: @escaping () -> Void) {
        self.model = model
        self.onOpenTilePilot = onOpenTilePilot
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
            onOpenTilePilot()
        }
    }

    private func presentQuickMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Open TilePilot", action: #selector(openTilePilot)))
        menu.addItem(item("Open Window Behavior", action: #selector(openWindowBehaviorSettings)))
        menu.addItem(item("Open Shortcuts", action: #selector(openShortcuts)))
        menu.addItem(.separator())

        let hasPinnedFeatures = addPinnedFeatureItems(to: menu)
        let hasPinnedShortcuts = addPinnedShortcutItems(to: menu)
        if hasPinnedFeatures || hasPinnedShortcuts {
            menu.addItem(.separator())
        }

        menu.addItem(.separator())
        let runtimeEnabled = model.canRunYabaiRuntimeCommands
        let runtimeReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"
        let hoverEnabled = model.windowBehaviorPolicyDraft.hoverFocusMode != .off
        let cursorFollowsFocus = model.windowBehaviorPolicyDraft.mouseFollowsFocusEnabled
        let autoTileNewWindows = !model.windowBehaviorPolicyDraft.manualTilingModeEnabled

        let hoverFocusItem = item(
            runtimeEnabled ? "Hover Focus" : "Hover Focus (\(runtimeReason))",
            action: #selector(toggleHoverFocus),
            enabled: runtimeEnabled
        )
        hoverFocusItem.state = hoverEnabled ? .on : .off
        menu.addItem(hoverFocusItem)

        let cursorFollowsFocusItem = item(
            runtimeEnabled ? "Cursor Follows Focus" : "Cursor Follows Focus (\(runtimeReason))",
            action: #selector(toggleMouseFollowsFocus),
            enabled: runtimeEnabled
        )
        cursorFollowsFocusItem.state = cursorFollowsFocus ? .on : .off
        menu.addItem(cursorFollowsFocusItem)

        let autoTileItem = item(
            runtimeEnabled ? "Auto-Tile New Windows" : "Auto-Tile New Windows (\(runtimeReason))",
            action: #selector(toggleAutoTileNewWindows),
            enabled: runtimeEnabled
        )
        autoTileItem.state = autoTileNewWindows ? .on : .off
        menu.addItem(autoTileItem)

        let raiseOnFloatItem = item(
            runtimeEnabled ? "Raise On Float Toggle" : "Raise On Float Toggle (\(runtimeReason))",
            action: #selector(toggleRaiseOnFloatToggle),
            enabled: runtimeEnabled
        )
        raiseOnFloatItem.state = model.raiseOnFloatToggleEnabled ? .on : .off
        menu.addItem(raiseOnFloatItem)

        let focusedAppName = model.focusedWindowState?.app.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusedAppAvailable = focusedAppName?.isEmpty == false
        let keepFocusedAppTitle: String
        if let focusedAppName, !focusedAppName.isEmpty {
            keepFocusedAppTitle = "Keep \(focusedAppName) on Top (When Floating)"
        } else {
            keepFocusedAppTitle = "Keep Focused App on Top (When Floating)"
        }
        let keepFocusedAppEnabled = runtimeEnabled && focusedAppAvailable
        let keepFocusedAppItem = item(
            keepFocusedAppEnabled ? keepFocusedAppTitle : "\(keepFocusedAppTitle) (\(runtimeEnabled ? "No focused app" : runtimeReason))",
            action: #selector(toggleFocusedAppKeepFrontWhenFloating),
            enabled: keepFocusedAppEnabled
        )
        if let focusedAppName, !focusedAppName.isEmpty {
            keepFocusedAppItem.state = model.appForegroundPolicy(for: focusedAppName) == .keepFrontWhenFloating ? .on : .off
        }
        menu.addItem(keepFocusedAppItem)

        let bringFloatingItem = item(
            runtimeEnabled ? "Keep Floating Windows on Top" : "Keep Floating Windows on Top (\(runtimeReason))",
            action: #selector(bringFloatingWindowsToFront),
            enabled: runtimeEnabled
        )
        menu.addItem(bringFloatingItem)

        let bringFlaggedFloatingItem = item(
            runtimeEnabled ? "Keep Flagged Floating Windows on Top" : "Keep Flagged Floating Windows on Top (\(runtimeReason))",
            action: #selector(bringFlaggedFloatingWindowsToFront),
            enabled: runtimeEnabled
        )
        menu.addItem(bringFlaggedFloatingItem)

        let badgeItem = item("Window Badges", action: #selector(toggleWindowBadgeOverlay))
        badgeItem.state = model.showWindowBadgeOverlay ? .on : .off
        menu.addItem(badgeItem)

        let outlineItem = item("Window Outline Overlay", action: #selector(toggleWindowOutlineOverlay))
        outlineItem.state = model.showWindowOutlineOverlay ? .on : .off
        menu.addItem(outlineItem)

        let balanceItem = item("Align Tiles (Balance)", action: #selector(runQuickAction(_:)), enabled: balanceTilesQuickActionEnabled())
        balanceItem.representedObject = TilePilotActionID.balanceSpace.rawValue
        menu.addItem(balanceItem)

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

    private func addPinnedFeatureItems(to menu: NSMenu) -> Bool {
        let pinned = model.pinnedFeatureControlRows
        if pinned.isEmpty {
            return false
        }
        for row in pinned {
            guard let featureID = row.featureID else { continue }
            let combo = row.shortcutEntry.map { model.displayShortcutComboSymbols($0) }
                ?? row.assignedCombo.map { model.displayShortcutComboSymbols(from: $0) }
                ?? row.defaultCombo.map { model.displayShortcutComboSymbols(from: $0) }
            let comboPrefix = (combo?.isEmpty == false) ? "\(combo!)  " : ""
            let label = comboPrefix + row.title
            let disabledReason = row.disabledReason
            let item = self.item(
                disabledReason == nil ? label : "\(label) (\(disabledReason!))",
                action: #selector(runPinnedFeature(_:)),
                enabled: disabledReason == nil
            )
            item.representedObject = featureID.rawValue
            menu.addItem(item)
        }
        return true
    }

    private func addPinnedShortcutItems(to menu: NSMenu) -> Bool {
        let pinnedGroups = model.pinnedDirectionalGroupBindings
        let pinnedRaw = model.pinnedShortcutEntries
        let pinned = pinnedRaw.filter { entry in
            // Feature-backed shortcuts now render through pinnedFeatureControlRows.
            if model.featureControlRow(forShortcutEntry: entry)?.featureID != nil {
                return false
            }
            return !(model.isScriptingAdditionDesktopShortcut(entry) && !model.canRunScriptingAdditionDesktopActions)
        }
        if pinnedGroups.isEmpty && pinned.isEmpty {
            return false
        }

        if !pinnedGroups.isEmpty {
            for group in pinnedGroups {
                addPinnedDirectionalGroupItems(to: menu, group: group.group, bindings: group.bindings)
            }
            if !pinned.isEmpty {
                menu.addItem(.separator())
            }
        }

        if !pinned.isEmpty {
            for entry in pinned {
                let title = pinnedShortcutMenuTitle(for: entry)
                let item = self.item(title, action: #selector(runPinnedShortcut(_:)))
                item.representedObject = entry.stableKey
                menu.addItem(item)
            }
        }
        return true
    }

    private func addPinnedDirectionalGroupItems(
        to menu: NSMenu,
        group: DirectionalShortcutGroup,
        bindings: [DirectionalShortcutBinding]
    ) {
        guard !bindings.isEmpty else { return }
        let header = NSMenuItem(title: "Pinned \(group.menuTitle)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for binding in bindings {
            let combo = model.displayShortcutComboSymbolsSpaced(binding.entry)
            let title = "\(combo)  \(binding.direction.arrow)  \(directionActionLabel(for: group, direction: binding.direction))"
            let item = self.item(title, action: #selector(runPinnedShortcut(_:)))
            item.representedObject = binding.entry.stableKey
            menu.addItem(item)
        }
    }

    private func directionActionLabel(
        for group: DirectionalShortcutGroup,
        direction: DirectionalShortcutDirection
    ) -> String {
        switch group {
        case .focusWindow:
            return "Focus \(direction.label)"
        case .moveWindow:
            return "Move \(direction.label)"
        case .resizeWindow:
            return "Resize \(direction.label)"
        case .swapWindow:
            return "Swap \(direction.label)"
        }
    }

    private func pinnedShortcutMenuTitle(for entry: ShortcutEntry) -> String {
        let symbols = model.displayShortcutComboSymbols(entry)
        let explanation = model.shortcutExplanation(entry)
        let combo = symbols.isEmpty ? model.displayShortcutComboWords(entry) : symbols
        let raw = "\(combo)  \(explanation)"
        if raw.count <= 72 { return raw }
        return String(raw.prefix(69)) + "..."
    }

    private func balanceTilesQuickActionEnabled() -> Bool {
        model.quickActionCards.first(where: { $0.id == .balanceSpace })?.enabled ?? false
    }

    @objc private func openTilePilot() { onOpenTilePilot() }

    @objc private func runDoctor() {
        model.acknowledgeInitialStatusIfNeeded()
        Task { await model.refreshDoctor() }
    }

    @objc private func disableHoverFocus() {
        model.acknowledgeInitialStatusIfNeeded()
        model.disableHoverFocus()
    }

    @objc private func toggleHoverFocus() {
        model.acknowledgeInitialStatusIfNeeded()
        if model.windowBehaviorPolicyDraft.hoverFocusMode == .off {
            model.setHoverFocusMode(.autofocus)
        } else {
            model.setHoverFocusMode(.off)
        }
    }

    @objc private func disableMouseFollowsFocus() {
        model.acknowledgeInitialStatusIfNeeded()
        model.disableMouseFollowsFocus()
    }

    @objc private func toggleMouseFollowsFocus() {
        model.acknowledgeInitialStatusIfNeeded()
        model.setMouseFollowsFocusEnabled(!model.windowBehaviorPolicyDraft.mouseFollowsFocusEnabled)
    }

    @objc private func enableManualTilingMode() {
        model.acknowledgeInitialStatusIfNeeded()
        model.enableManualTilingMode()
    }

    @objc private func disableManualTilingMode() {
        model.acknowledgeInitialStatusIfNeeded()
        model.disableManualTilingMode()
    }

    @objc private func toggleAutoTileNewWindows() {
        model.acknowledgeInitialStatusIfNeeded()
        if model.windowBehaviorPolicyDraft.manualTilingModeEnabled {
            model.disableManualTilingMode()
        } else {
            model.enableManualTilingMode()
        }
    }

    @objc private func toggleRaiseOnFloatToggle() {
        model.acknowledgeInitialStatusIfNeeded()
        model.toggleRaiseOnFloatToggle()
    }

    @objc private func toggleFocusedAppKeepFrontWhenFloating() {
        model.acknowledgeInitialStatusIfNeeded()
        guard let appName = model.focusedWindowState?.app.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty else {
            model.lastErrorMessage = "No focused app detected."
            model.lastActionMessage = nil
            return
        }
        model.toggleKeepFrontWhenFloating(for: appName)
    }

    @objc private func bringFloatingWindowsToFront() {
        model.acknowledgeInitialStatusIfNeeded()
        model.bringFloatingWindowsToFrontCurrentDesktop()
    }

    @objc private func bringFlaggedFloatingWindowsToFront() {
        model.acknowledgeInitialStatusIfNeeded()
        model.bringFlaggedFloatingWindowsToFrontCurrentDesktop()
    }

    @objc private func toggleWindowBadgeOverlay() {
        model.acknowledgeInitialStatusIfNeeded()
        model.toggleWindowBadgeOverlay()
    }

    @objc private func toggleWindowOutlineOverlay() {
        model.acknowledgeInitialStatusIfNeeded()
        model.toggleWindowOutlineOverlay()
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
        onOpenTilePilot()
    }

    @objc private func openShortcuts() {
        model.acknowledgeInitialStatusIfNeeded()
        model.requestOpenTilePilotTab(.shortcuts)
        onOpenTilePilot()
    }

    @objc private func runSetupInstaller() {
        model.acknowledgeInitialStatusIfNeeded()
        model.runSetupInstallerInTerminal()
    }

    @objc private func runQuickAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let id = TilePilotActionID(rawValue: raw) else { return }
        model.acknowledgeInitialStatusIfNeeded()
        model.performTilePilotAction(id)
    }

    @objc private func runPinnedShortcut(_ sender: NSMenuItem) {
        guard let stableKey = sender.representedObject as? String else { return }
        model.acknowledgeInitialStatusIfNeeded()
        model.runPinnedShortcut(stableKey: stableKey)
    }

    @objc private func runPinnedFeature(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        model.acknowledgeInitialStatusIfNeeded()
        model.runFeatureControl(FeatureControlID(rawValue: raw), source: .statusMenu)
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
    private var tilePilotWindowController: TilePilotWindowController?
    private var statusBarController: StatusBarController?
    private var windowBadgeOverlayController: WindowBadgeOverlayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        tilePilotWindowController = TilePilotWindowController(model: model)
        statusBarController = StatusBarController(model: model) { [weak self] in
            self?.model.acknowledgeInitialStatusIfNeeded()
            self?.tilePilotWindowController?.showAndFocus()
        }
        windowBadgeOverlayController = WindowBadgeOverlayController(model: model)

        model.startIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        tilePilotWindowController?.showAndFocus()
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

    func applicationWillTerminate(_ notification: Notification) {
        windowBadgeOverlayController = nil
    }
}
