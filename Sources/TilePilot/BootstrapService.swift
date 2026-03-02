import ApplicationServices
import Foundation

struct BootstrapRunResult: Sendable {
    let snapshot: SetupBootstrapSnapshot
    let commandLogs: [CommandLogEntry]
}

final class BootstrapService: @unchecked Sendable {
    static let startAtLogonLaunchAgentLabel = "com.klode.tilepilot.launcher"
    static let startAtLogonLaunchAgentFileName = "com.klode.tilepilot.launcher.plist"

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
            commandLogs: logs
        )
    }

    func prepareInstallerScript() throws -> URL {
        let fm = FileManager.default
        let supportDirectory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TilePilot/Setup", isDirectory: true)
        try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

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
        let supportDirectory = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TilePilot/Setup", isDirectory: true)
        try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

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
            detail: trusted ? "Granted" : "Not granted (optional). The app still works without this."
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
        """
        #!/bin/zsh
        set -u

        clear
        echo "=============================================="
        echo " TilePilot Setup Installer (fresh mac helper)"
        echo "=============================================="
        echo
        echo "This script installs Homebrew (if needed), yabai, and skhd."
        echo "Some steps may prompt for admin password or user confirmation."
        echo

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
          echo "  Triggering xcode-select installer (GUI). Complete it, then re-run this script if needed."
          /usr/bin/xcode-select --install || true
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
          read -k 1 '?Press any key to close...'
          echo
          exit 1
        fi
        echo "  Brew: $(brew --version | head -n 1)"
        echo

        echo "Step 3: Install yabai + skhd"
        brew update
        brew tap koekeishiya/formulae
        brew install yabai skhd
        echo

        echo "Step 4: Start background services (best effort)"
        /usr/bin/env yabai --start-service || true
        /usr/bin/env skhd --start-service || true
        echo "  (If your installed version does not support --start-service, start them using your preferred launch method.)"
        echo

        echo "Step 5: Next steps (manual)"
        echo "  - Open TilePilot and use 'Request Accessibility Access'"
        echo "  - In TilePilot > System, enable 'Start at logon'"
        echo "  - Enable TilePilot in Accessibility settings"
        echo "  - Verify Mission Control settings in TilePilot > Health"
        echo "  - Desktop switching/move-window shortcuts may require yabai scripting addition + SIP configuration"
        echo
        echo "Installed versions:"
        /usr/bin/env yabai --version || true
        /usr/bin/env skhd --version || true
        echo
        echo "Finished. Return to TilePilot and run 'Check System'."
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
        echo " TilePilot: Fix yabai Scripting Addition"
        echo "=============================================="
        echo
        echo "This repairs the yabai scripting addition used by core desktop actions"
        echo "(switch desktop, move window to desktop, etc.)."
        echo
        echo "You will be prompted for your admin password (sudo)."
        echo "If this fails, macOS version compatibility or SIP configuration may be the reason."
        echo

        ensure_path() {
          export PATH="/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/sbin:/usr/local/sbin:$PATH"
        }

        ensure_path

        if ! /usr/bin/env yabai --version >/dev/null 2>&1; then
          echo "ERROR: yabai is not installed or not in PATH."
          echo "Use TilePilot -> System -> Install Dependencies first."
          echo
          read -k 1 '?Press any key to close...'
          echo
          exit 1
        fi

        echo "Detected: $(/usr/bin/env yabai --version)"
        echo
        echo "Step 1: Uninstall existing scripting addition (best effort)"
        /usr/bin/sudo /usr/bin/env yabai --uninstall-sa || true
        echo
        YABAI_HELP="$(/usr/bin/env yabai --help 2>&1 || true)"
        SA_LOAD_CMD=""
        if [[ "$YABAI_HELP" == *"--load-sa"* ]]; then
          SA_LOAD_CMD="--load-sa"
        elif [[ "$YABAI_HELP" == *"--install-sa"* ]]; then
          SA_LOAD_CMD="--install-sa"
        fi

        if [ -z "$SA_LOAD_CMD" ]; then
          echo "ERROR: This yabai version does not expose a known scripting-addition install/load command."
          echo "Expected one of: --load-sa or --install-sa"
          echo
          echo "Detected help output:"
          echo "$YABAI_HELP" | head -n 20
          echo
          read -k 1 '?Press any key to close...'
          echo
          exit 1
        fi

        echo "Step 2: Install/load scripting addition ($SA_LOAD_CMD)"
        SA_OUTPUT="$({ /usr/bin/sudo /usr/bin/env yabai "$SA_LOAD_CMD"; } 2>&1)"
        SA_EXIT=$?
        echo "$SA_OUTPUT"
        if [ $SA_EXIT -ne 0 ]; then
          echo
          echo "Install failed."
          echo "Common reasons:"
          echo "  - SIP configuration does not allow scripting addition injection"
          echo "  - macOS update changed compatibility"
          echo "  - yabai version / install mismatch"
          if [[ "$SA_OUTPUT" == *"System Integrity Protection"* ]]; then
            echo
            echo "Your output indicates SIP is still blocking scripting-addition support."
            echo "Desktop switching / move-window shortcuts that target desktops will keep failing until SIP is configured for yabai's scripting addition requirements."
          fi
          echo
          read -k 1 '?Press any key to close...'
          echo
          exit 1
        fi
        echo
        echo "Step 3: Scripting addition command completed"
        if [[ "$SA_LOAD_CMD" != "--load-sa" ]]; then
          echo "Running --load-sa (if available) to load the installed scripting addition..."
          /usr/bin/sudo /usr/bin/env yabai --load-sa || true
        else
          echo "Already loaded via --load-sa."
        fi
        echo
        echo "Step 4: Restart yabai service (best effort)"
        /usr/bin/env yabai --restart-service || true
        echo
        echo "Back in TilePilot:"
        echo "  1) Run Check System"
        echo "  2) Try Option+1 (or a Desktop shortcut) again"
        echo "  3) If it still fails, review the Health section and command logs"
        echo
        read -k 1 '?Press any key to close...'
        echo
        """
    }
}
