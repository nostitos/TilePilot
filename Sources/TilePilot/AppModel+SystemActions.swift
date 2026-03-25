import AppKit
import ApplicationServices
import Foundation

@MainActor
extension AppModel {
    private var helperService: ManagedHelperService {
        ManagedHelperService.shared
    }

    func exportDiagnostics() {
        guard let snapshot = doctorSnapshot else {
            lastErrorMessage = "Run System Recheck before exporting diagnostics."
            return
        }

        let report = DiagnosticsReport(
            generatedAt: Date(),
            systemProfile: snapshot.systemProfile,
            health: snapshot,
            capabilities: snapshot.capabilities,
            recentCommands: Array(commandLogs.prefix(50))
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(report)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("tilepilot-diagnostics-\(stamp).json")
            try data.write(to: url, options: .atomic)
            lastExportURL = url
            lastErrorMessage = nil
            lastActionMessage = "Diagnostics exported to \(url.lastPathComponent)"
        } catch {
            lastErrorMessage = "Diagnostics export failed: \(error.localizedDescription)"
        }
    }

    func copyIssueReadySummary() {
        guard let snapshot = doctorSnapshot else {
            lastErrorMessage = "Run System Recheck before copying a status summary."
            return
        }

        let failing = snapshot.capabilities
            .filter { $0.status != .available }
            .sorted { $0.status.severityRank > $1.status.severityRank }

        var lines: [String] = []
        lines.append("TilePilot Status Summary")
        lines.append("Generated: \(snapshot.generatedAt.formatted(date: .abbreviated, time: .standard))")
        lines.append("macOS: \(snapshot.systemProfile.macOSVersion)")
        lines.append("Build: \(snapshot.systemProfile.macOSBuild ?? "unknown")")
        lines.append("Arch: \(snapshot.systemProfile.arch)")
        lines.append("yabai: \(snapshot.systemProfile.yabaiVersion ?? "not detected")")
        lines.append("skhd: \(snapshot.systemProfile.skhdVersion ?? "not detected")")
        lines.append("Health: \(snapshot.healthBadge.title)")
        lines.append("")
        lines.append("Capabilities:")
        for item in failing.prefix(8) {
            lines.append("- \(item.key): \(item.status.rawValue) (\(item.reasonCode ?? "no-reason"))")
            lines.append("  \(item.message)")
        }
        if !snapshot.compatibilityWarnings.isEmpty {
            lines.append("")
            lines.append("Warnings:")
            snapshot.compatibilityWarnings.forEach { lines.append("- \($0)") }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        lastErrorMessage = nil
        lastActionMessage = "Issue-ready summary copied to clipboard."
    }

    func installManagedHelpers() {
        Task { [weak self] in
            guard let self else { return }
            let existingInstalls = await self.helperService.detectExistingExternalHelpers()

            if !existingInstalls.isEmpty {
                await MainActor.run {
                    self.helperMigrationPrompt = HelperMigrationPromptState(installs: existingInstalls)
                    self.lastErrorMessage = nil
                    self.lastActionMessage = "TilePilot found an existing yabai/skhd install. Choose whether to keep it or replace it."
                }
                return
            }

            await self.performManagedHelperInstall(replacingExternalInstall: false)
        }
    }

    func keepExistingHelperInstall() {
        helperMigrationPrompt = nil
        lastErrorMessage = nil
        lastActionMessage = "Keeping the existing yabai/skhd install. TilePilot will use the external binaries."
        Task { [weak self] in
            await self?.refreshBootstrapSetup()
            await self?.refreshDoctor()
        }
    }

    func replaceWithManagedHelpers() {
        guard !isLaunchingSetupInstaller else { return }
        helperMigrationPrompt = nil
        Task { [weak self] in
            guard let self else { return }
            await self.performManagedHelperInstall(replacingExternalInstall: true)
        }
    }

    func dismissHelperMigrationPrompt() {
        helperMigrationPrompt = nil
    }

    private func performManagedHelperInstall(replacingExternalInstall: Bool) async {
        await MainActor.run {
            self.isLaunchingSetupInstaller = true
        }

        let result = replacingExternalInstall
            ? await self.helperService.installBundledHelpersReplacingExternalServices()
            : await self.helperService.installBundledHelpers()

        await MainActor.run {
            self.isLaunchingSetupInstaller = false
            self.applyManagedHelperOperationResult(result)
        }

        await self.refreshBootstrapSetup()
        await self.refreshDoctor()
    }

    func runSetupInstallerInTerminal() {
        installManagedHelpers()
    }

    func runScriptingAdditionRepairInTerminal() {
        acknowledgeInitialStatusIfNeeded()
        lastErrorMessage = "This desktop-control repair flow is not supported by TilePilot."
        lastActionMessage = nil
    }

    func openSystemSettings() {
        openURLCandidates([
            "x-apple.systempreferences:",
        ])
    }

    func openAccessibilitySettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:",
        ])
    }

    func requestAccessibilityAccessPrompt() {
        acknowledgeInitialStatusIfNeeded()
        let alreadyTrusted = AXIsProcessTrusted()
        if alreadyTrusted {
            lastActionMessage = "Accessibility access is already granted."
            lastErrorMessage = nil
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        lastActionMessage = "Requested Accessibility access prompt. If no prompt appears, open Accessibility Settings manually."
        lastErrorMessage = nil
        scheduleSetupRefreshAfterExternalHandoff(delaySeconds: 1.0)
    }

    func requestScreenRecordingAccessPrompt() {
        acknowledgeInitialStatusIfNeeded()
        let alreadyAuthorized = megamapCaptureService.screenRecordingAuthorized()
        if alreadyAuthorized {
            megamapScreenRecordingAuthorized = true
            lastActionMessage = "Screen Recording access is already granted."
            lastErrorMessage = nil
            return
        }

        _ = megamapCaptureService.requestScreenRecordingAccess()
        megamapScreenRecordingAuthorized = megamapCaptureService.screenRecordingAuthorized()
        megamapCaptureService.openScreenRecordingSettings()
        if megamapScreenRecordingAuthorized {
            lastActionMessage = "Screen Recording access confirmed."
            lastErrorMessage = nil
        } else {
            lastActionMessage = "Opened Screen Recording settings."
            lastErrorMessage = "If TilePilot is not listed yet, macOS has not registered the capture request. Reopen TilePilot and try Enable Screen Recording again."
        }
        scheduleSetupRefreshAfterExternalHandoff(delaySeconds: 1.0)
    }

    func openScreenRecordingSettings() {
        acknowledgeInitialStatusIfNeeded()
        _ = megamapCaptureService.requestScreenRecordingAccess()
        megamapCaptureService.openScreenRecordingSettings()
        lastActionMessage = "Opened Screen Recording settings."
        lastErrorMessage = "If TilePilot is not listed yet, macOS has not registered the capture request. Reopen TilePilot and try Enable Screen Recording again."
        scheduleSetupRefreshAfterExternalHandoff(delaySeconds: 1.0)
    }

    func openMissionControlSettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.preference.expose",
            "x-apple.systempreferences:",
        ])
    }

    func openMissionControlKeyboardShortcuts() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts=MissionControl",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts/MissionControl",
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?KeyboardShortcuts",
            "x-apple.systempreferences:com.apple.preference.keyboard?KeyboardShortcutsTab",
            "x-apple.systempreferences:com.apple.preference.keyboard",
            "x-apple.systempreferences:",
        ])
    }

    func openLoginItemsSettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.systempreferences.GeneralSettings",
            "x-apple.systempreferences:",
        ])
    }

    func enableStartAtLogon() {
        acknowledgeInitialStatusIfNeeded()

        let fm = FileManager.default
        let launchAgentsDirectory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsDirectory
            .appendingPathComponent(BootstrapService.startAtLogonLaunchAgentFileName)

        do {
            try fm.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            let plist = startAtLogonLaunchAgentPlist()
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            lastActionMessage = "Enabled start at logon."
            lastErrorMessage = nil
            Task { [weak self] in
                await self?.refreshBootstrapSetup()
            }
        } catch {
            lastErrorMessage = "Failed to enable start at logon: \(error.localizedDescription)"
            lastActionMessage = nil
        }
    }

    func restartYabaiBestEffort() {
        if helperService.hasManagedHelperInstall() {
            runSupportCommand(
                yabaiCommand(["--restart-service"], timeout: 2.0),
                successMessage: "Requested yabai service restart."
            )
        } else {
            runSupportCommand(
                yabaiCommand(["--start-service"], timeout: 2.0),
                successMessage: "Requested yabai service start."
            )
        }
    }

    func restartSkhdBestEffort() {
        Task { [weak self] in
            guard let self else { return }
            let reloadResult = await self.doctorService.runSupportCommand(
                skhdCommand(["--reload"], timeout: 2.0)
            )
            var fallbackResult: CommandResult?

            if !reloadResult.isSuccess {
                let fallbackCommand = helperService.hasManagedHelperInstall()
                    ? skhdCommand(["--restart-service"], timeout: 2.0)
                    : skhdCommand(["--start-service"], timeout: 2.0)
                fallbackResult = await self.doctorService.runSupportCommand(fallbackCommand)
            }

            await MainActor.run {
                self.appendCommandLog(from: reloadResult)
                if let fallbackResult {
                    self.appendCommandLog(from: fallbackResult)
                }

                if reloadResult.isSuccess {
                    self.lastActionMessage = "Requested skhd config reload."
                    self.lastErrorMessage = nil
                } else if fallbackResult?.isSuccess == true {
                    self.lastActionMessage = helperService.hasManagedHelperInstall()
                        ? "Requested skhd service restart."
                        : "Requested skhd service start."
                    self.lastErrorMessage = nil
                } else {
                    let stderrReload = reloadResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    let stderrFallback = fallbackResult?.stderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let stderr = [stderrReload, stderrFallback].filter { !$0.isEmpty }.joined(separator: " | ")
                    self.lastErrorMessage = stderr.isEmpty
                        ? "Could not restart skhd."
                        : "skhd reload/start failed: \(trimForUI(stderr))"
                    self.lastActionMessage = nil
                }
            }

            await self.refreshBootstrapSetup()
            await self.refreshDoctor()
        }
    }

    func startBrewServiceYabai() {
        startYabaiBestEffort()
    }

    func startBrewServiceSkhd() {
        startSkhdBestEffort()
    }

    func startYabaiBestEffort() {
        if helperService.hasManagedHelperInstall() {
            startHelperServicesBestEffort()
            return
        }

        runSupportCommand(
            yabaiCommand(["--start-service"], timeout: 2.0),
            successMessage: "Requested yabai service start."
        )
    }

    func startSkhdBestEffort() {
        if helperService.hasManagedHelperInstall() {
            startHelperServicesBestEffort()
            return
        }

        runSupportCommand(
            skhdCommand(["--start-service"], timeout: 2.0),
            successMessage: "Requested skhd service start."
        )
    }

    func startHelperServicesBestEffort() {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isLaunchingSetupInstaller = true
            }
            let result = await self.helperService.startManagedServices()

            await MainActor.run {
                self.isLaunchingSetupInstaller = false
                self.applyManagedHelperOperationResult(result)
            }

            await self.refreshBootstrapSetup()
            await self.refreshDoctor()
        }
    }

    private func openURLCandidates(_ candidates: [String], updateMessaging: Bool = true) {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                if updateMessaging {
                    lastActionMessage = "Opened System Settings."
                    lastErrorMessage = nil
                }
                return
            }
        }
        if updateMessaging {
            lastErrorMessage = "Unable to open System Settings."
        }
    }

    private func startAtLogonLaunchAgentPlist() -> String {
        let appPath = Bundle.main.bundlePath
        let escapedAppPath = xmlEscaped(appPath)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(BootstrapService.startAtLogonLaunchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-a</string>
                <string>\(escapedAppPath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func applyManagedHelperOperationResult(_ result: ManagedHelperOperationResult) {
        managedHelperInstallState = result.installState
        prependCommandLogs(result.commandLogs.reversed())
        if let errorMessage = result.errorMessage {
            lastErrorMessage = errorMessage
            lastActionMessage = nil
        } else {
            lastActionMessage = result.successMessage ?? "TilePilot helpers updated."
            lastErrorMessage = nil
        }
    }

    private func scheduleSetupRefreshAfterExternalHandoff(delaySeconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            await self?.refreshBootstrapSetup()
            await self?.refreshDoctor()
        }
    }
}
