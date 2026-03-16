import ApplicationServices
import Foundation

struct BootstrapRunResult: Sendable {
    let snapshot: SetupBootstrapSnapshot
    let externalInstallerStatus: ExternalInstallerStatus?
    let commandLogs: [CommandLogEntry]
}

final class BootstrapService: @unchecked Sendable {
    static let startAtLogonLaunchAgentLabel = "com.klode.tilepilot.launcher"
    static let startAtLogonLaunchAgentFileName = "com.klode.tilepilot.launcher.plist"
    static let setupDirectoryRelativePath = "Library/Application Support/TilePilot/Setup"
    static let installerStatusFileName = "installer_status.json"

    private let runner = CommandRunner()

    func runBootstrapChecks() async -> BootstrapRunResult {
        async let xcodeSelectTask = runner.run(.init("/usr/bin/xcode-select", ["-p"], timeout: 1.0))
        async let brewVersionTask = runner.run(.init("/usr/bin/env", ["brew", "--version"], timeout: 1.5))
        async let brewPrefixTask = runner.run(.init("/usr/bin/env", ["brew", "--prefix"], timeout: 1.5))
        async let brewTapTask = runner.run(.init("/usr/bin/env", ["brew", "tap"], timeout: 2.0))
        async let brewServicesTask = runner.run(.init("/usr/bin/env", ["brew", "services", "list"], timeout: 2.0))
        async let yabaiVersionTask = runner.run(.init("/usr/bin/env", ["yabai", "--version"], timeout: 1.5))
        async let skhdVersionTask = runner.run(.init("/usr/bin/env", ["skhd", "--version"], timeout: 1.5))
        async let yabaiProcessTask = runner.run(.init("/usr/bin/env", ["pgrep", "-x", "yabai"], timeout: 1.0))
        async let skhdProcessTask = runner.run(.init("/usr/bin/env", ["pgrep", "-x", "skhd"], timeout: 1.0))

        let xcodeSelect = await xcodeSelectTask
        let brewVersion = await brewVersionTask
        let brewPrefix = await brewPrefixTask
        let brewTap = await brewTapTask
        let brewServices = await brewServicesTask
        let yabaiVersion = await yabaiVersionTask
        let skhdVersion = await skhdVersionTask
        let yabaiProcess = await yabaiProcessTask
        let skhdProcess = await skhdProcessTask

        let brewInstalled = brewVersion.isSuccess
        let brewPrefixText = cleanedLine(from: brewPrefix.stdout)

        let items = [
            xcodeCLTItem(from: xcodeSelect),
            homebrewItem(from: brewVersion),
            brewTapItem(from: brewTap, brewInstalled: brewInstalled),
            binaryItem(id: "yabai-binary", title: "yabai", versionResult: yabaiVersion),
            binaryItem(id: "skhd-binary", title: "skhd", versionResult: skhdVersion),
            brewServiceItem(name: "yabai", servicesResult: brewServices, brewInstalled: brewInstalled, processResult: yabaiProcess),
            brewServiceItem(name: "skhd", servicesResult: brewServices, brewInstalled: brewInstalled, processResult: skhdProcess),
            startAtLogonItem(),
            accessibilityItem(),
        ]

        let logs = [xcodeSelect, brewVersion, brewPrefix, brewTap, brewServices, yabaiVersion, skhdVersion, yabaiProcess, skhdProcess].map(makeLog)

        return BootstrapRunResult(
            snapshot: SetupBootstrapSnapshot(
                generatedAt: Date(),
                items: items,
                brewPrefix: brewInstalled ? brewPrefixText : nil
            ),
            externalInstallerStatus: loadExternalInstallerStatus(),
            commandLogs: logs
        )
    }

    func prepareInstallerScript() throws -> URL {
        let fm = FileManager.default
        let supportDirectory = try Self.setupSupportDirectory(fileManager: fm)

        let scriptURL = supportDirectory.appendingPathComponent("install_yabai_stack.command")
        let script = installerScriptContents()
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = scriptURL
        try? mutableURL.setResourceValues(values)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    func prepareScriptingAdditionRepairScript() throws -> URL {
        let fm = FileManager.default
        let supportDirectory = try Self.setupSupportDirectory(fileManager: fm)

        let scriptURL = supportDirectory.appendingPathComponent("repair_yabai_scripting_addition.command")
        let script = scriptingAdditionRepairScriptContents()
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = scriptURL
        try? mutableURL.setResourceValues(values)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    func loadExternalInstallerStatus() -> ExternalInstallerStatus? {
        let url = Self.installerStatusURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ExternalInstallerStatus.self, from: data)
        } catch {
            return nil
        }
    }

    static func installerStatusURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(setupDirectoryRelativePath, isDirectory: true)
            .appendingPathComponent(installerStatusFileName)
    }

    private static func setupSupportDirectory(fileManager: FileManager) throws -> URL {
        let supportDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(setupDirectoryRelativePath, isDirectory: true)
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        return supportDirectory
    }

    private func xcodeCLTItem(from result: CommandResult) -> SetupCheckItem {
        if result.isSuccess, let path = cleanedLine(from: result.stdout), !path.isEmpty {
            return SetupCheckItem(id: "xcode-clt", title: "Xcode Command Line Tools", state: .installed, detail: "Installed at \(path)")
        }

        let detail: String
        if result.stderr.localizedCaseInsensitiveContains("active developer directory") {
            detail = "Not installed. Installer can trigger `xcode-select --install`."
        } else {
            detail = "Unable to confirm CLT installation."
        }
        return SetupCheckItem(id: "xcode-clt", title: "Xcode Command Line Tools", state: .missing, detail: detail)
    }

    private func homebrewItem(from result: CommandResult) -> SetupCheckItem {
        if result.isSuccess, let line = cleanedLine(from: result.stdout), !line.isEmpty {
            return SetupCheckItem(id: "homebrew", title: "Homebrew", state: .installed, detail: line)
        }
        return SetupCheckItem(
            id: "homebrew",
            title: "Homebrew",
            state: .missing,
            detail: "Homebrew not detected in PATH. Installer can install it."
        )
    }

    private func brewTapItem(from result: CommandResult, brewInstalled: Bool) -> SetupCheckItem {
        guard brewInstalled else {
            return SetupCheckItem(
                id: "brew-tap-koekeishiya",
                title: "Homebrew tap koekeishiya/formulae",
                state: .unknown,
                detail: "Homebrew is not installed yet."
            )
        }
        if result.isSuccess, result.stdout.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "koekeishiya/formulae" }) {
            return SetupCheckItem(
                id: "brew-tap-koekeishiya",
                title: "Homebrew tap koekeishiya/formulae",
                state: .installed,
                detail: "Tap is present."
            )
        }
        return SetupCheckItem(
            id: "brew-tap-koekeishiya",
            title: "Homebrew tap koekeishiya/formulae",
            state: .missing,
            detail: "Tap missing. Installer will add it."
        )
    }

    private func binaryItem(id: String, title: String, versionResult: CommandResult) -> SetupCheckItem {
        if versionResult.isSuccess, let line = cleanedLine(from: versionResult.stdout), !line.isEmpty {
            return SetupCheckItem(id: id, title: title, state: .installed, detail: line)
        }
        return SetupCheckItem(id: id, title: title, state: .missing, detail: "\(title) not detected in PATH.")
    }

    private func brewServiceItem(name: String, servicesResult: CommandResult, brewInstalled: Bool, processResult: CommandResult) -> SetupCheckItem {
        let title = "\(name) service"
        guard brewInstalled else {
            return SetupCheckItem(id: "brew-service-\(name)", title: title, state: .unknown, detail: "Homebrew is not installed yet.")
        }
        let processRunning = processResult.isSuccess
        let processDetail = processRunning ? "Running." : "Not running."

        guard servicesResult.isSuccess else {
            return SetupCheckItem(id: "brew-service-\(name)", title: title, state: processRunning ? .installed : .unknown, detail: processRunning ? processDetail : "Unable to read service status.")
        }

        let rows = parseBrewServicesList(servicesResult.stdout)
        guard let status = rows[name] else {
            if processRunning {
                return SetupCheckItem(
                    id: "brew-service-\(name)",
                    title: title,
                    state: .installed,
                    detail: "Running (not listed in brew services; managed by \(name) --start-service)."
                )
            }
            return SetupCheckItem(
                id: "brew-service-\(name)",
                title: title,
                state: .missing,
                detail: "Not running yet. Use Start Service."
            )
        }

        let normalized = status.lowercased()
        if normalized == "started" {
            return SetupCheckItem(id: "brew-service-\(name)", title: title, state: .installed, detail: "Started")
        }
        if normalized == "none" || normalized == "stopped" {
            if processRunning {
                return SetupCheckItem(id: "brew-service-\(name)", title: title, state: .installed, detail: "Running (\(status) in brew services).")
            }
            return SetupCheckItem(id: "brew-service-\(name)", title: title, state: .warning, detail: "Installed but not running (\(status)).")
        }
        if processRunning {
            return SetupCheckItem(id: "brew-service-\(name)", title: title, state: .installed, detail: "Running (service status: \(status)).")
        }
        return SetupCheckItem(id: "brew-service-\(name)", title: title, state: .warning, detail: "Status: \(status)")
    }

    private func accessibilityItem() -> SetupCheckItem {
        let trusted = AXIsProcessTrusted()
        return SetupCheckItem(
            id: "accessibility-permission",
            title: "Optional: TilePilot Accessibility permission",
            state: trusted ? .installed : .unknown,
            detail: trusted ? "Granted" : "TilePilot could not confirm this permission right now. The app still works without it."
        )
    }

    private func startAtLogonItem() -> SetupCheckItem {
        let launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(Self.startAtLogonLaunchAgentFileName)
        if FileManager.default.fileExists(atPath: launchAgentURL.path) {
            return SetupCheckItem(
                id: "start-at-logon",
                title: "Start TilePilot at logon",
                state: .installed,
                detail: "Configured via \(launchAgentURL.path)."
            )
        }
        return SetupCheckItem(
            id: "start-at-logon",
            title: "Start TilePilot at logon",
            state: .warning,
            detail: "Not enabled. Recommended for menu bar availability after sign-in."
        )
    }

    private func parseBrewServicesList(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("Name ") || line.hasPrefix("name ") {
                continue
            }
            let columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if columns.count >= 2 {
                result[columns[0]] = columns[1]
            }
        }
        return result
    }

    private func cleanedLine(from output: String) -> String? {
        output
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeLog(from result: CommandResult) -> CommandLogEntry {
        CommandLogEntry(
            id: UUID(),
            command: result.command,
            startedAt: result.startedAt,
            endedAt: result.endedAt,
            durationMs: result.durationMs,
            exitStatus: result.exitStatus,
            stdoutSnippet: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description,
            stderrSnippet: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description,
            errorType: result.errorType
        )
    }

    private func installerScriptContents() -> String {
        let installerStatusPath = Self.installerStatusURL().path
        return """
        #!/bin/zsh
        set -euo pipefail

        INSTALLER_STATUS_FILE="\(installerStatusPath)"

        clear
        echo "=============================================="
        echo " TilePilot Setup Installer (fresh mac helper)"
        echo "=============================================="
        echo
        echo "This script installs Homebrew (if needed), yabai, and skhd."
        echo "Some steps may prompt for admin password or user confirmation."
        echo

        write_status() {
          local outcome="$1"
          local blocker="$2"
          local action="$3"
          local summary="$4"
          local escaped_summary="${summary//\\/\\\\}"
          escaped_summary="${escaped_summary//\"/\\\"}"
          local escaped_blocker="null"
          if [ -n "$blocker" ]; then
            escaped_blocker="\"$blocker\""
          fi
          /bin/mkdir -p "$(dirname "$INSTALLER_STATUS_FILE")"
          cat > "$INSTALLER_STATUS_FILE" <<EOF
        {
          "outcome": "$outcome",
          "blocker": $escaped_blocker,
          "summary": "$escaped_summary",
          "recommendedAction": "$action",
          "updatedAt": "$(/bin/date -u +"%Y-%m-%dT%H:%M:%SZ")"
        }
        EOF
        }

        finish_with_error() {
          local message="$1"
          echo
          echo "Setup stopped."
          echo "$message"
          echo
          echo "Return to TilePilot after fixing this step. TilePilot will recheck setup when you come back."
          read -k 1 '?Press any key to close...'
          echo
          exit 1
        }

        run_or_fail() {
          local label="$1"
          shift
          local output=""
          local exit_code=0
          set +e
          output="$("$@" 2>&1)"
          exit_code=$?
          set -e
          if [ $exit_code -ne 0 ]; then
            echo "$output"
            echo
            finish_with_error "$label failed."
          fi
          echo "$output"
        }

        ensure_brew_shellenv() {
          if [ -x /opt/homebrew/bin/brew ]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
          elif [ -x /usr/local/bin/brew ]; then
            eval "$(/usr/local/bin/brew shellenv)"
          fi
          export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        }

        echo "Step 1: Check Xcode Command Line Tools"
        if /usr/bin/xcode-select -p >/dev/null 2>&1; then
          echo "  OK: Command Line Tools already installed."
        else
          echo "  Command Line Tools not detected."
          echo "  Triggering xcode-select installer (GUI)."
          echo "  Complete that install, then re-run this script."
          echo "  A reboot is usually not required."
          write_status "blocked" "apple_developer_tools_missing" "updateAppleDeveloperTools" "Apple Developer Tools are required before TilePilot helpers can be installed."
          /usr/bin/xcode-select --install || true
          echo
          finish_with_error "Command Line Tools are required before yabai and skhd can be installed."
        fi
        echo

        echo "Step 2: Check Homebrew"
        if ! /usr/bin/which brew >/dev/null 2>&1; then
          echo "  Homebrew not found. Installing..."
          /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        else
          echo "  OK: Homebrew already installed."
        fi
        ensure_brew_shellenv
        if ! /usr/bin/which brew >/dev/null 2>&1; then
          echo "  ERROR: Homebrew still not available in PATH."
          write_status "failed" "homebrew_failed" "installHelpers" "TilePilot could not make Homebrew available in Terminal."
          finish_with_error "Homebrew still is not available in PATH."
        fi
        echo "  Brew: $(brew --version | head -n 1)"
        echo

        echo "Step 3: Install yabai + skhd"
        run_or_fail "Homebrew update" brew update
        run_or_fail "Homebrew tap koekeishiya/formulae" brew tap koekeishiya/formulae

        install_output=""
        install_exit=0
        set +e
        install_output="$(brew install yabai skhd 2>&1)"
        install_exit=$?
        set -e
        echo "$install_output"
        if [ $install_exit -ne 0 ]; then
          echo
          if [[ "$install_output" == *"Command Line Tools are too outdated"* ]]; then
            write_status "blocked" "apple_developer_tools_outdated" "updateAppleDeveloperTools" "Apple Developer Tools are too old for installing TilePilot helpers."
            finish_with_error $'Homebrew could not install yabai and skhd because your Xcode Command Line Tools are too old.\n\nUpdate them in System Settings > Software Update, or run:\n  sudo rm -rf /Library/Developer/CommandLineTools\n  xcode-select --install\n\nThen re-run this installer. A reboot is usually not required.'
          fi
          write_status "failed" "helper_install_failed" "installHelpers" "TilePilot helpers could not be installed. Fix the Terminal error and rerun the installer."
          finish_with_error "Homebrew could not install yabai and skhd. Review the error above, fix it, then re-run this installer."
        fi

        if ! /usr/bin/env yabai --version >/dev/null 2>&1; then
          write_status "failed" "helper_install_failed" "installHelpers" "yabai did not become available after install."
          finish_with_error "Homebrew finished without making yabai available in PATH. Re-open Terminal and re-run this installer."
        fi
        if ! /usr/bin/env skhd --version >/dev/null 2>&1; then
          write_status "failed" "helper_install_failed" "installHelpers" "skhd did not become available after install."
          finish_with_error "Homebrew finished without making skhd available in PATH. Re-open Terminal and re-run this installer."
        fi
        echo

        echo "Step 4: Start background services (best effort)"
        service_start_failed=0
        /usr/bin/env yabai --start-service || { echo "  yabai installed, but automatic service start did not complete."; service_start_failed=1; }
        /usr/bin/env skhd --start-service || { echo "  skhd installed, but automatic service start did not complete."; service_start_failed=1; }
        echo "  (If your installed version does not support --start-service, start them using your preferred launch method.)"
        echo

        echo "Step 5: Next steps (manual)"
        echo "  - Open TilePilot and use 'Request Accessibility Access'"
        echo "  - In TilePilot > System, enable 'Start at logon'"
        echo "  - Enable TilePilot in Accessibility settings"
        echo "  - Verify Mission Control settings in TilePilot > Health"
        echo
        echo "Installed versions:"
        /usr/bin/env yabai --version || true
        /usr/bin/env skhd --version || true
        echo
        if [ "$service_start_failed" -eq 1 ]; then
          write_status "success" "service_start_failed" "startHelperServices" "TilePilot helpers were installed, but the background services still need to be started."
        else
          write_status "success" "" "ready" "TilePilot helpers were installed successfully."
        fi
        echo "Finished. Return to TilePilot. It will recheck setup automatically. No reboot should be required."
        read -k 1 '?Press any key to close...'
        echo
        """
    }

    private func scriptingAdditionRepairScriptContents() -> String {
        """
        #!/bin/zsh
        set -u

        clear
        echo "=============================================="
        echo " TilePilot: Unsupported Desktop Control"
        echo "=============================================="
        echo
        echo "TilePilot does not support this desktop-control repair flow."
        echo
        echo "If you need unsupported yabai desktop-control features,"
        echo "handle that setup manually outside TilePilot."
        echo
        read -k 1 '?Press any key to close...'
        echo
        """
    }
}
