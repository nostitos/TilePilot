import AppKit
import ApplicationServices
import Foundation

@MainActor
extension AppModel {
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

    func runSetupInstallerInTerminal() {
        guard !isLaunchingSetupInstaller else { return }
        isLaunchingSetupInstaller = true

        Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.isLaunchingSetupInstaller = false } }

            do {
                let scriptURL = try self.bootstrapService.prepareInstallerScript()
                let openResult = await self.doctorService.runSupportCommand(
                    ShellCommand("/usr/bin/open", ["-a", "Terminal", scriptURL.path], timeout: 3.0)
                )

                await MainActor.run {
                    self.lastSetupInstallerURL = scriptURL
                    self.appendCommandLog(from: openResult)
                    if openResult.isSuccess {
                        self.lastActionMessage = "Opened TilePilot Helper installer in Terminal."
                        self.lastErrorMessage = nil
                        self.scheduleSetupRefreshAfterExternalHandoff(delaySeconds: 1.5)
                    } else {
                        self.lastErrorMessage = "Failed to open installer in Terminal. Try opening \(scriptURL.path) manually."
                        self.lastActionMessage = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastErrorMessage = "Failed to prepare setup installer: \(error.localizedDescription)"
                    self.lastActionMessage = nil
                }
            }
        }
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

    func requestXcodeCLTInstallPrompt() {
        acknowledgeInitialStatusIfNeeded()
        runSupportCommand(
            ShellCommand("/usr/bin/xcode-select", ["--install"], timeout: 2.0),
            successMessage: "Requested Apple Developer Tools installer prompt. If nothing appears, check System Settings > Software Update."
        )
        openSoftwareUpdateSettings()
        scheduleSetupRefreshAfterExternalHandoff(delaySeconds: 1.5)
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

    func openMissionControlSettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.preference.expose",
            "x-apple.systempreferences:",
        ])
    }

    func openSoftwareUpdateSettings() {
        openURLCandidates([
            "x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.softwareupdate",
            "x-apple.systempreferences:",
        ], updateMessaging: false)
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
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "--restart-service"], timeout: 2.0),
            successMessage: "Requested yabai service restart."
        )
    }

    func restartSkhdBestEffort() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["skhd", "--reload"], timeout: 2.0),
            successMessage: "Requested skhd config reload."
        )
    }

    func startBrewServiceYabai() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["yabai", "--start-service"], timeout: 5.0),
            successMessage: "Requested `yabai --start-service`."
        )
    }

    func startBrewServiceSkhd() {
        runSupportCommand(
            ShellCommand("/usr/bin/env", ["skhd", "--start-service"], timeout: 5.0),
            successMessage: "Requested `skhd --start-service`."
        )
    }

    func startHelperServicesBestEffort() {
        Task { [weak self] in
            guard let self else { return }
            let yabaiResult = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["yabai", "--start-service"], timeout: 5.0)
            )
            let skhdResult = await self.doctorService.runSupportCommand(
                ShellCommand("/usr/bin/env", ["skhd", "--start-service"], timeout: 5.0)
            )

            await MainActor.run {
                self.appendCommandLog(from: yabaiResult)
                self.appendCommandLog(from: skhdResult)
                if yabaiResult.isSuccess && skhdResult.isSuccess {
                    self.lastActionMessage = "Requested helper services start."
                    self.lastErrorMessage = nil
                } else {
                    self.lastErrorMessage = "TilePilot could not start one or more helper services automatically."
                    self.lastActionMessage = nil
                }
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

    private func scheduleSetupRefreshAfterExternalHandoff(delaySeconds: Double) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            await self?.refreshBootstrapSetup()
            await self?.refreshDoctor()
        }
    }
}
