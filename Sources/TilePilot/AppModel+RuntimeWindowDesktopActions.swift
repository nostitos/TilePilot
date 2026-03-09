import AppKit
import ApplicationServices
import Foundation

@MainActor
extension AppModel {
    func bringFloatingWindowsToFrontCurrentDesktop() {
        Task { [weak self] in
            guard let self else { return }
            await self.bringFloatingWindowsToFrontCurrentDesktop(
                flaggedOnly: false,
                reason: .manualAll,
                bypassCooldown: true
            )
        }
    }

    func bringFlaggedFloatingWindowsToFrontCurrentDesktop(reason: String = "manual") {
        Task { [weak self] in
            guard let self else { return }
            let internalReason: FloatingBringReason = reason == "auto" ? .autoTransition : .manualFlagged
            await self.bringFloatingWindowsToFrontCurrentDesktop(
                flaggedOnly: true,
                reason: internalReason,
                bypassCooldown: internalReason != .autoTransition
            )
        }
    }

    func tileFocusedWindowNow() {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        setWindowFloating(windowID: focused.id, shouldFloat: false, bringToFrontOnFloat: true)
    }

    func floatFocusedWindowNow() {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        setWindowFloating(windowID: focused.id, shouldFloat: true, bringToFrontOnFloat: true)
    }

    func toggleFocusedWindowTiling() {
        guard let focused = focusedWindowState else {
            lastErrorMessage = "No focused window detected."
            lastActionMessage = nil
            return
        }
        toggleWindowFloating(windowID: focused.id, bringToFrontOnFloat: true)
    }

    func focusWindow(windowID: Int) {
        guard let window = focusableWindow(windowID: windowID) else { return }
        Task { [weak self] in
            guard let self else { return }
            let focus = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--focus", String(windowID)], timeout: 1.5)
            )
            await MainActor.run {
                self.appendCommandLog(from: focus)
            }
            guard focus.isSuccess else {
                await MainActor.run {
                    self.lastErrorMessage = "Could not focus \(window.app)."
                    self.lastActionMessage = nil
                }
                return
            }
            await MainActor.run {
                self.lastActionMessage = "Focused \(window.app)."
                self.lastErrorMessage = nil
            }
            await self.refreshLiveState()
        }
    }

    func focusWindow(windowID: Int, desktopIndex: Int) {
        guard let window = focusableWindow(windowID: windowID) else { return }
        Task { [weak self] in
            guard let self else { return }

            if let currentSpace = await self.queryCurrentFocusedSpaceIndex(),
               currentSpace != desktopIndex {
                let switched = await self.focusDesktopInternal(index: desktopIndex, updateMessages: false)
                guard switched else {
                    await MainActor.run {
                        self.lastErrorMessage = "Could not switch to Desktop \(desktopIndex)."
                        self.lastActionMessage = nil
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(180))
            }

            let focus = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--focus", String(windowID)], timeout: 1.5)
            )
            await MainActor.run {
                self.appendCommandLog(from: focus)
            }
            guard focus.isSuccess else {
                await MainActor.run {
                    self.lastErrorMessage = "Could not focus \(window.app)."
                    self.lastActionMessage = nil
                }
                return
            }

            await MainActor.run {
                self.lastActionMessage = "Focused \(window.app)."
                self.lastErrorMessage = nil
            }
            await self.refreshLiveState()
        }
    }

    func focusDesktop(index: Int) {
        Task { [weak self] in
            guard let self else { return }
            let switched = await self.focusDesktopInternal(index: index, updateMessages: true)
            guard switched else { return }
            await self.refreshLiveState()
        }
    }

    func desktopTilingEnabled(spaceIndex: Int) -> Bool? {
        guard let snapshot = liveStateSnapshot, snapshot.source == .yabai, !snapshot.degraded else { return nil }
        guard let layout = snapshot.spaces.first(where: { $0.index == spaceIndex })?.layout?.lowercased() else { return nil }
        if layout == "float" { return false }
        if layout == "bsp" || layout == "stack" { return true }
        return nil
    }

    func desktopTilingDisabledReason(spaceIndex: Int) -> String? {
        guard canRunYabaiRuntimeCommands else {
            return yabaiRuntimeControlDisabledReason ?? "Desktop controls are unavailable."
        }
        guard let snapshot = liveStateSnapshot, snapshot.source == .yabai, !snapshot.degraded else {
            return "Desktop layout data is unavailable right now."
        }
        guard snapshot.spaces.contains(where: { $0.index == spaceIndex }) else {
            return "Desktop \(spaceIndex) is not currently available."
        }
        return nil
    }

    func setDesktopTilingEnabled(spaceIndex: Int, enabled: Bool) {
        if let reason = desktopTilingDisabledReason(spaceIndex: spaceIndex) {
            lastErrorMessage = reason
            lastActionMessage = nil
            return
        }
        if let current = desktopTilingEnabled(spaceIndex: spaceIndex), current == enabled {
            lastActionMessage = enabled ? "Desktop \(spaceIndex) tiling is already on." : "Desktop \(spaceIndex) tiling is already off."
            lastErrorMessage = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let targetLayout = enabled ? "bsp" : "float"
            let result = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "space", String(spaceIndex), "--layout", targetLayout], timeout: 1.5)
            )
            await MainActor.run {
                self.appendCommandLog(from: result)
                if result.isSuccess {
                    self.lastActionMessage = enabled ? "Desktop \(spaceIndex) tiling enabled." : "Desktop \(spaceIndex) tiling disabled."
                    self.lastErrorMessage = nil
                } else {
                    self.lastErrorMessage = enabled
                        ? "Failed to enable tiling on Desktop \(spaceIndex)."
                        : "Failed to disable tiling on Desktop \(spaceIndex)."
                    self.lastActionMessage = nil
                }
            }
            guard result.isSuccess else { return }
            await self.refreshLiveState()
            await self.refreshDoctor()
        }
    }

    func setAllDesktopTilingEnabled(enabled: Bool) {
        guard canRunYabaiRuntimeCommands else {
            lastErrorMessage = yabaiRuntimeControlDisabledReason ?? "Desktop controls are unavailable."
            lastActionMessage = nil
            return
        }
        guard let snapshot = liveStateSnapshot, snapshot.source == .yabai, !snapshot.degraded else {
            lastErrorMessage = "Desktop layout data is unavailable right now."
            lastActionMessage = nil
            return
        }
        let targetSpaces = snapshot.spaces.map(\.index).sorted()
        guard !targetSpaces.isEmpty else {
            lastErrorMessage = "No desktops available."
            lastActionMessage = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let targetLayout = enabled ? "bsp" : "float"
            var successCount = 0
            for spaceIndex in targetSpaces {
                let result = await self.doctorService.runSupportCommand(
                    ShellCommand("/usr/bin/env", ["yabai", "-m", "space", String(spaceIndex), "--layout", targetLayout], timeout: 1.5)
                )
                await MainActor.run {
                    self.appendCommandLog(from: result)
                }
                if result.isSuccess {
                    successCount += 1
                }
            }
            await MainActor.run {
                if successCount == targetSpaces.count {
                    self.lastActionMessage = enabled ? "Enabled tiling on all desktops." : "Disabled tiling on all desktops."
                    self.lastErrorMessage = nil
                } else {
                    self.lastActionMessage = enabled
                        ? "Enabled tiling on \(successCount)/\(targetSpaces.count) desktops."
                        : "Disabled tiling on \(successCount)/\(targetSpaces.count) desktops."
                    self.lastErrorMessage = "Some desktops could not be updated."
                }
            }
            await self.refreshLiveState()
            await self.refreshDoctor()
        }
    }

    func toggleWindowFloating(windowID: Int, bringToFrontOnFloat: Bool = false) {
        guard let window = runtimeControllableWindow(windowID: windowID) else { return }
        setWindowFloating(windowID: windowID, shouldFloat: !window.floating, bringToFrontOnFloat: bringToFrontOnFloat)
    }

    func setWindowFloating(windowID: Int, shouldFloat: Bool, bringToFrontOnFloat: Bool = false) {
        guard let window = runtimeControllableWindow(windowID: windowID) else { return }
        if window.floating == shouldFloat {
            lastActionMessage = shouldFloat ? "\(window.app) is already floating." : "\(window.app) is already tiled."
            lastErrorMessage = nil
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let toggle = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "-m", "window", String(windowID), "--toggle", "float"], timeout: 1.5)
            )
            await MainActor.run {
                self.appendCommandLog(from: toggle)
                if !toggle.isSuccess {
                    self.lastErrorMessage = shouldFloat ? "Failed to set window to floating." : "Failed to set window to tiled."
                    self.lastActionMessage = nil
                }
            }
            guard toggle.isSuccess else { return }

            let foregroundPolicyEnabled = self.appForegroundPolicy(for: window.app) == .keepFrontWhenFloating
            if shouldFloat && (bringToFrontOnFloat || self.raiseOnFloatToggleEnabled || foregroundPolicyEnabled) {
                let shouldAllowFocusFallback = bringToFrontOnFloat || self.raiseOnFloatToggleEnabled
                _ = await self.raiseWindowOnly(
                    windowID: windowID,
                    targetSpace: window.space,
                    bypassCooldown: true,
                    allowFocusFallback: shouldAllowFocusFallback
                )
            }
            if shouldFloat && foregroundPolicyEnabled {
                await self.bringFloatingWindowsToFrontCurrentDesktop(
                    flaggedOnly: true,
                    reason: .floatToggle,
                    bypassCooldown: false
                )
            }

            await MainActor.run {
                self.lastActionMessage = shouldFloat ? "Window set to floating." : "Window set to tiled."
                self.lastErrorMessage = nil
            }
            await self.refreshLiveState()
        }
    }

    func openWindowBehaviorSettings() {
        requestOpenTilePilotTab(.windowBehavior)
    }

    func openTilePilotDashboard() {
        acknowledgeInitialStatusIfNeeded()
        requestOpenTilePilotTab(.now)
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { window in
            window.styleMask.contains(.titled) && window.title == "TilePilot"
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    func openShortcutsDashboard() {
        acknowledgeInitialStatusIfNeeded()
        requestOpenTilePilotTab(.shortcuts)
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { window in
            window.styleMask.contains(.titled) && window.title == "TilePilot"
        }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
    }

    func openShortcutSource(_ entry: ShortcutEntry) {
        selectShortcut(entry)
        requestOpenFile(path: entry.sourceFile, line: entry.sourceLine)
    }

    var canRunYabaiRuntimeCommands: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return map["yabai-binary"] == .available && map["yabai-daemon"] == .available
    }

    var canRunScriptingAdditionDesktopActions: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return map["scripting-addition"] == .available
    }

    func isScriptingAdditionDesktopShortcut(_ entry: ShortcutEntry) -> Bool {
        entry.command.lowercased().contains("yabai -m window --space")
    }

    var yabaiRuntimeControlDisabledReason: String? {
        guard let snapshot = doctorSnapshot else { return "Open System and run Recheck first." }
        let map = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0) })
        if map["yabai-binary"]?.status != .available {
            return map["yabai-binary"]?.message ?? "yabai is not installed."
        }
        if map["yabai-daemon"]?.status != .available {
            return map["yabai-daemon"]?.message ?? "yabai is not running."
        }
        return nil
    }

    private struct MissionControlDesktopBinding {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private func isScriptingAdditionDesktopFocusFailure(_ result: CommandResult) -> Bool {
        let text = "\(result.stderr)\n\(result.stdout)".lowercased()
        return (text.contains("cannot focus space") && text.contains("scripting-addition"))
            || (text.contains("cannot focus space") && text.contains("scripting addition"))
    }

    private func focusDesktopInternal(index: Int, updateMessages: Bool) async -> Bool {
        let result = await self.doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "space", "--focus", String(index)], timeout: 1.5)
        )
        await MainActor.run {
            self.appendCommandLog(from: result)
        }
        if result.isSuccess {
            if updateMessages {
                await MainActor.run {
                    self.lastActionMessage = "Switched to Desktop \(index)."
                    self.lastErrorMessage = nil
                }
            }
            return true
        }

        if await self.focusAnyWindowOnDesktop(index: index) {
            if updateMessages {
                await MainActor.run {
                    self.lastActionMessage = "Switched to Desktop \(index)."
                    self.lastErrorMessage = nil
                }
            }
            return true
        }

        if self.isScriptingAdditionDesktopFocusFailure(result),
           self.triggerMissionControlDesktopShortcut(index: index) {
            if updateMessages {
                await MainActor.run {
                    self.lastActionMessage = "Switched to Desktop \(index) using macOS shortcut fallback."
                    self.lastErrorMessage = nil
                }
            }
            return true
        }

        if updateMessages {
            await MainActor.run {
                self.lastErrorMessage = "Could not switch to Desktop \(index)."
                self.lastActionMessage = nil
            }
        }
        return false
    }

    private func focusAnyWindowOnDesktop(index: Int) async -> Bool {
        let query = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "query", "--windows", "--space", String(index)], timeout: 1.2)
        )
        await MainActor.run {
            appendCommandLog(from: query)
        }
        guard query.isSuccess,
              let data = query.stdout.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !rows.isEmpty else {
            return false
        }

        let sorted = rows.sorted { lhs, rhs in
            let lhsAX = boolFromAny(lhs["has-ax-reference"]) == true
            let rhsAX = boolFromAny(rhs["has-ax-reference"]) == true
            if lhsAX != rhsAX { return lhsAX && !rhsAX }
            let lhsMove = boolFromAny(lhs["can-move"]) == true
            let rhsMove = boolFromAny(rhs["can-move"]) == true
            if lhsMove != rhsMove { return lhsMove && !rhsMove }
            let lhsID = intFromAny(lhs["id"]) ?? Int.max
            let rhsID = intFromAny(rhs["id"]) ?? Int.max
            return lhsID < rhsID
        }

        guard let targetID = sorted.compactMap({ intFromAny($0["id"]) }).first else {
            return false
        }

        let focus = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "window", "--focus", String(targetID)], timeout: 1.2)
        )
        await MainActor.run {
            appendCommandLog(from: focus)
        }
        return focus.isSuccess
    }

    private func triggerMissionControlDesktopShortcut(index: Int) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let binding = missionControlDesktopBinding(for: index)
            ?? missionControlDefaultBinding(for: index)
        guard let binding else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: binding.keyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = binding.flags
        keyUp.flags = binding.flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func missionControlDesktopBinding(for desktopIndex: Int) -> MissionControlDesktopBinding? {
        guard (1...16).contains(desktopIndex) else { return nil }
        let actionID = String(117 + desktopIndex)

        guard let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
              let allHotKeys = domain["AppleSymbolicHotKeys"] as? [String: Any],
              let entry = allHotKeys[actionID] as? [String: Any] else {
            return nil
        }

        guard boolFromAny(entry["enabled"]) == true else { return nil }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any],
              parameters.count >= 3,
              let keyCodeInt = intFromAny(parameters[1]),
              let modifierInt = intFromAny(parameters[2]),
              keyCodeInt >= 0 else {
            return nil
        }

        return MissionControlDesktopBinding(
            keyCode: CGKeyCode(keyCodeInt),
            flags: CGEventFlags(rawValue: UInt64(modifierInt))
        )
    }

    private func missionControlDefaultBinding(for desktopIndex: Int) -> MissionControlDesktopBinding? {
        let keyCode: Int
        switch desktopIndex {
        case 1: keyCode = 18
        case 2: keyCode = 19
        case 3: keyCode = 20
        case 4: keyCode = 21
        case 5: keyCode = 23
        case 6: keyCode = 22
        case 7: keyCode = 26
        case 8: keyCode = 28
        case 9: keyCode = 25
        case 10: keyCode = 29
        default: return nil
        }
        return MissionControlDesktopBinding(
            keyCode: CGKeyCode(keyCode),
            flags: .maskControl
        )
    }

    private func boolFromAny(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }

    private func intFromAny(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    func queryCurrentFocusedSpaceIndex() async -> Int? {
        let result = await doctorService.runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "-m", "query", "--spaces", "--space"], timeout: 1.0)
        )
        await MainActor.run {
            appendCommandLog(from: result)
        }
        guard result.isSuccess,
              let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let index = object["index"] as? Int { return index }
        if let number = object["index"] as? NSNumber { return number.intValue }
        return nil
    }

    private func runtimeControllableWindow(windowID: Int) -> WindowState? {
        guard canRunYabaiRuntimeCommands else {
            lastErrorMessage = yabaiRuntimeControlDisabledReason ?? "Window controls are unavailable right now."
            lastActionMessage = nil
            return nil
        }
        guard let window = liveStateSnapshot?.windows.first(where: { $0.id == windowID }) else {
            lastErrorMessage = "Window is no longer available."
            lastActionMessage = nil
            return nil
        }
        guard window.isRuntimeManageable else {
            lastErrorMessage = "\(window.app) does not expose move/control hooks for this window right now, so TilePilot cannot tile/float it."
            lastActionMessage = nil
            return nil
        }
        return window
    }

    private func focusableWindow(windowID: Int) -> WindowState? {
        guard canRunYabaiRuntimeCommands else {
            lastErrorMessage = yabaiRuntimeControlDisabledReason ?? "Window controls are unavailable right now."
            lastActionMessage = nil
            return nil
        }
        guard let window = liveStateSnapshot?.windows.first(where: { $0.id == windowID }) else {
            lastErrorMessage = "Window is no longer available."
            lastActionMessage = nil
            return nil
        }
        return window
    }
}
