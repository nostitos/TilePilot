import AppKit
import Combine
import SwiftUI

@MainActor
final class TilePilotWindowController: NSWindowController, NSWindowDelegate {
    private enum PersistedWindowSizeKeys {
        static let width = "TilePilot.mainWindow.width"
        static let height = "TilePilot.mainWindow.height"
        static let frameAutosaveName = "TilePilotMainWindow"
    }

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
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()
        _ = window.setFrameUsingName(PersistedWindowSizeKeys.frameAutosaveName)
        Self.restorePersistedSize(for: window)
        window.setFrameAutosaveName(PersistedWindowSizeKeys.frameAutosaveName)

        super.init(window: window)
        shouldCascadeWindows = true
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func showAndFocus() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func persistCurrentWindowSize() {
        guard let window else { return }
        persist(size: window.frame.size)
        window.saveFrame(usingName: PersistedWindowSizeKeys.frameAutosaveName)
    }

    func windowWillClose(_ notification: Notification) {
        persistCurrentWindowSize()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistCurrentWindowSize()
    }

    private static func restorePersistedSize(for window: NSWindow) {
        let defaults = UserDefaults.standard
        let persistedWidth = CGFloat(defaults.double(forKey: PersistedWindowSizeKeys.width))
        let persistedHeight = CGFloat(defaults.double(forKey: PersistedWindowSizeKeys.height))
        guard persistedWidth > 0, persistedHeight > 0 else { return }

        let minWidth = window.minSize.width
        let minHeight = window.minSize.height
        let maxFrame = NSScreen.main?.visibleFrame.size
        let maxWidth = maxFrame?.width ?? persistedWidth
        let maxHeight = maxFrame?.height ?? persistedHeight

        let width = min(max(persistedWidth, minWidth), maxWidth)
        let height = min(max(persistedHeight, minHeight), maxHeight)
        var frame = window.frame
        frame.size = NSSize(width: width, height: height)
        window.setFrame(frame, display: false)
    }

    private func persist(size: NSSize) {
        let defaults = UserDefaults.standard
        defaults.set(size.width, forKey: PersistedWindowSizeKeys.width)
        defaults.set(size.height, forKey: PersistedWindowSizeKeys.height)
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let onOpenTilePilot: () -> Void
    private let onQuit: () -> Void
    private let statusItem: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel, onOpenTilePilot: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.model = model
        self.onOpenTilePilot = onOpenTilePilot
        self.onQuit = onQuit
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
        menu.addItem(openTilePilotMenuItem())
        menu.addItem(item("Open Window Behavior", action: #selector(openWindowBehaviorSettings)))
        menu.addItem(item("Open Shortcuts", action: #selector(openShortcuts)))
        menu.addItem(.separator())

        if addPinnedContextItems(to: menu) {
            menu.addItem(.separator())
        }

        menu.addItem(.separator())
        let runtimeEnabled = model.canRunYabaiRuntimeCommands
        let runtimeReason = model.yabaiRuntimeControlDisabledReason ?? "Unavailable"
        let hoverEnabled = model.windowBehaviorPolicyDraft.hoverFocusMode != .off
        let cursorFollowsFocus = model.windowBehaviorPolicyDraft.mouseFollowsFocusEnabled

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

        let badgeItem = item("Window Badges", action: #selector(toggleWindowBadgeOverlay))
        badgeItem.state = model.showWindowBadgeOverlay ? .on : .off
        menu.addItem(badgeItem)

        let outlineItem = item("Window Outline Overlay", action: #selector(toggleWindowOutlineOverlay))
        outlineItem.state = model.showWindowOutlineOverlay ? .on : .off
        menu.addItem(outlineItem)

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

    private func openTilePilotMenuItem() -> NSMenuItem {
        let menuItem = item("Open TilePilot", action: #selector(openTilePilot))
        if let row = model.featureControlRow(forID: FeatureControlID(rawValue: "app.open-tilepilot")) {
            let comboRaw = row.shortcutEntry?.combo ?? row.assignedCombo ?? row.defaultCombo
            applyMenuShortcut(to: menuItem, comboRaw: comboRaw)
        }
        return menuItem
    }

    private func addPinnedContextItems(to menu: NSMenu) -> Bool {
        let pinnedItems = model.pinnedShortcutContextItems
        guard !pinnedItems.isEmpty else { return false }

        for item in pinnedItems {
            switch item {
            case .feature(let row):
                guard let featureID = row.featureID else { continue }
                let disabledReason = row.disabledReason
                let leftLabel = disabledReason == nil ? row.title : "\(row.title) (\(disabledReason!))"
                let menuItem = self.item(
                    leftLabel,
                    action: #selector(runPinnedFeature(_:)),
                    enabled: disabledReason == nil
                )
                let comboRaw = row.shortcutEntry?.combo ?? row.assignedCombo ?? row.defaultCombo
                applyMenuShortcut(to: menuItem, comboRaw: comboRaw)
                menuItem.representedObject = featureID.rawValue
                menu.addItem(menuItem)
            case .directional(let group, let bindings):
                addPinnedDirectionalGroupItems(to: menu, group: group, bindings: bindings)
            case .shortcut(let entry):
                let menuItem = self.item(model.shortcutTitle(entry), action: #selector(runPinnedShortcut(_:)))
                applyMenuShortcut(to: menuItem, comboRaw: entry.combo)
                menuItem.representedObject = entry.stableKey
                menu.addItem(menuItem)
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
            let title = "\(binding.direction.arrow)  \(directionActionLabel(for: group, direction: binding.direction))"
            let item = self.item(title, action: #selector(runPinnedShortcut(_:)))
            applyMenuShortcut(to: item, comboRaw: binding.entry.combo)
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

    private struct ParsedMenuShortcut {
        let keyEquivalent: String
        let modifiers: NSEvent.ModifierFlags
    }

    private func applyMenuShortcut(to item: NSMenuItem, comboRaw: String?) {
        guard let parsed = parseMenuShortcut(comboRaw) else { return }
        item.keyEquivalent = parsed.keyEquivalent
        item.keyEquivalentModifierMask = parsed.modifiers
    }

    private func parseMenuShortcut(_ comboRaw: String?) -> ParsedMenuShortcut? {
        guard let comboRaw, !comboRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let normalized = comboRaw.replacingOccurrences(of: "—", with: "-")
        guard let splitIndex = normalized.lastIndex(of: "-") else { return nil }

        let modifiersPart = String(normalized[..<splitIndex]).lowercased()
        let keyPartRaw = String(normalized[normalized.index(after: splitIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyPartRaw.isEmpty else { return nil }
        let keyToken = keyPartRaw
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .first?
            .lowercased() ?? keyPartRaw.lowercased()

        guard let keyEquivalent = menuKeyEquivalent(for: keyToken) else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        let modifierTokens = modifiersPart
            .replacingOccurrences(of: "+", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).lowercased() }
        for token in modifierTokens {
            switch token {
            case "shift":
                modifiers.insert(.shift)
            case "alt", "option":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            case "cmd", "command":
                modifiers.insert(.command)
            default:
                continue
            }
        }

        return ParsedMenuShortcut(keyEquivalent: keyEquivalent, modifiers: modifiers)
    }

    private func menuKeyEquivalent(for token: String) -> String? {
        if token == "0x32" { return "`" }
        if token.count == 1 { return token.lowercased() }
        switch token {
        case "space":
            return " "
        case "tab":
            return "\t"
        case "return", "enter":
            return "\r"
        case "escape", "esc":
            return String(UnicodeScalar(0x1B)!)
        case "left":
            return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case "right":
            return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case "up":
            return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case "down":
            return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        default:
            return nil
        }
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
        onQuit()
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
        if shouldTerminateAsDuplicateInstance() {
            NSApplication.shared.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)

        tilePilotWindowController = TilePilotWindowController(model: model)
        statusBarController = StatusBarController(
            model: model,
            onOpenTilePilot: { [weak self] in
                self?.model.acknowledgeInitialStatusIfNeeded()
                self?.tilePilotWindowController?.showAndFocus()
            },
            onQuit: { [weak self] in
                self?.tilePilotWindowController?.persistCurrentWindowSize()
                NSApplication.shared.terminate(nil)
            }
        )
        windowBadgeOverlayController = WindowBadgeOverlayController(model: model)

        model.startIfNeeded()

        // Accessory apps can otherwise look "dead" if the status item is missing or hidden.
        // Surface the main window on launch so manual launches always produce visible UI.
        DispatchQueue.main.async { [weak self] in
            self?.tilePilotWindowController?.showAndFocus()
        }
    }

    private func shouldTerminateAsDuplicateInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard instances.count > 1 else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let keeperPID = instances.map(\.processIdentifier).min() ?? currentPID
        return currentPID != keeperPID
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

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleDeepLink(url)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "tilepilot" else { return }
        let host = url.host?.lowercased() ?? ""
        guard host == "feature" else { return }
        let featureRaw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).removingPercentEncoding ?? ""
        guard !featureRaw.isEmpty else { return }

        model.acknowledgeInitialStatusIfNeeded()
        Task { [weak self] in
            guard let self else { return }
            await self.model.refreshLiveState()
            self.model.runFeatureControl(FeatureControlID(rawValue: featureRaw), source: .shortcutsUI)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tilePilotWindowController?.persistCurrentWindowSize()
        windowBadgeOverlayController = nil
    }
}
