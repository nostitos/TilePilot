import Foundation

enum YabaiRulesConfigServiceError: LocalizedError {
    case malformedManagedMarkers
    case backupNotFound
    case io(String)

    var errorDescription: String? {
        switch self {
        case .malformedManagedMarkers:
            return "Found only one TilePilot yabai-config marker, or markers are out of order."
        case .backupNotFound:
            return "Selected backup file no longer exists."
        case .io(let message):
            return message
        }
    }
}

final class YabaiRulesConfigService: @unchecked Sendable {
    let beginMarker = "# >>> TILEPILOT YABAI CONFIG BEGIN"
    let endMarker = "# <<< TILEPILOT YABAI CONFIG END"

    func loadConfigDocument() async throws -> YabaiConfigDocumentState {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try self.loadConfigDocumentSync())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveWindowBehaviorPolicy(_ policy: ManagedWindowBehaviorPolicy) async throws -> YabaiConfigSaveResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try self.saveWindowBehaviorPolicySync(policy))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func restoreBackup(path: String) async throws -> YabaiConfigRestoreResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try self.restoreBackupSync(path: path))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func buildManagedSectionDiff(original: String, proposed: String) -> String {
        let oldLines = original.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let newLines = proposed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if oldLines == newLines { return "No changes." }

        var output: [String] = ["--- current managed section", "+++ proposed managed section"]
        let diff = newLines.difference(from: oldLines)
        for change in diff {
            switch change {
            case .remove(_, let element, _): output.append("- \(element)")
            case .insert(_, let element, _): output.append("+ \(element)")
            }
        }
        return output.joined(separator: "\n")
    }

    func renderManagedBody(for policy: ManagedWindowBehaviorPolicy) -> String {
        var lines: [String] = []
        lines.append("# Managed by TilePilot. Unknown lines outside this block are preserved.")
        lines.append("yabai -m config focus_follows_mouse \(policy.hoverFocusMode.rawValue)")
        lines.append("yabai -m config mouse_follows_focus \(policy.mouseFollowsFocusEnabled ? "on" : "off")")

        for app in policy.alwaysTileApps.map(normalizeAppName).filter({ !$0.isEmpty }).sorted() {
            let label = ruleLabel(prefix: "tp_always", appName: app)
            lines.append("yabai -m rule --add label=\(label) app=\"\(escapeRegex(app))\" manage=on")
        }
        for app in policy.neverTileApps.map(normalizeAppName).filter({ !$0.isEmpty }).sorted() {
            let label = ruleLabel(prefix: "tp_never", appName: app)
            lines.append("yabai -m rule --add label=\(label) app=\"\(escapeRegex(app))\" manage=off")
        }
        if policy.manualTilingModeEnabled {
            lines.append("yabai -m rule --add label=tp_manual_tiling_default app=\".*\" manage=off")
        }
        return lines.joined(separator: "\n")
    }

    func runtimeRuleCommands(previous: ManagedWindowBehaviorPolicy, current: ManagedWindowBehaviorPolicy) -> [ShellCommand] {
        var commands: [ShellCommand] = []

        let previousLabels = ruleLabels(for: previous)
        let currentLabels = ruleLabels(for: current)
        for label in Array(previousLabels.union(currentLabels)).sorted() {
            commands.append(yabaiCommand(["-m", "rule", "--remove", "label=\(label)"], timeout: 1.5))
        }

        for app in current.alwaysTileApps.map(normalizeAppName).filter({ !$0.isEmpty }).sorted() {
            commands.append(
                yabaiCommand([
                    "-m", "rule", "--add",
                    "label=\(ruleLabel(prefix: "tp_always", appName: app))",
                    "app=\(escapeRegex(app))",
                    "manage=on",
                ], timeout: 1.5)
            )
        }
        for app in current.neverTileApps.map(normalizeAppName).filter({ !$0.isEmpty }).sorted() {
            commands.append(
                yabaiCommand([
                    "-m", "rule", "--add",
                    "label=\(ruleLabel(prefix: "tp_never", appName: app))",
                    "app=\(escapeRegex(app))",
                    "manage=off",
                ], timeout: 1.5)
            )
        }
        if current.manualTilingModeEnabled {
            commands.append(
                yabaiCommand([
                    "-m", "rule", "--add",
                    "label=tp_manual_tiling_default",
                    "app=.*",
                    "manage=off",
                ], timeout: 1.5)
            )
        }
        return commands
    }

    func parsePolicy(fromManagedBody body: String) -> ManagedWindowBehaviorPolicy {
        var policy = ManagedWindowBehaviorPolicy.default
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.contains("config focus_follows_mouse ") {
                if trimmed.contains(" autoraise") {
                    policy.hoverFocusMode = .autoraise
                } else if trimmed.contains(" autofocus") {
                    policy.hoverFocusMode = .autofocus
                } else if trimmed.contains(" off") {
                    policy.hoverFocusMode = .off
                }
                continue
            }
            if trimmed.contains("config mouse_follows_focus ") {
                if trimmed.contains(" on") || trimmed.contains(" true") || trimmed.contains(" 1") {
                    policy.mouseFollowsFocusEnabled = true
                } else if trimmed.contains(" off") || trimmed.contains(" false") || trimmed.contains(" 0") {
                    policy.mouseFollowsFocusEnabled = false
                }
                continue
            }

            if trimmed.contains(#"rule --add label=tp_manual_tiling_default app=".*" manage=off"#) ||
               trimmed.contains(#"rule --add app=".*" manage=off"#) {
                policy.manualTilingModeEnabled = true
                continue
            }

            guard trimmed.contains("rule --add"), let app = parseAppPattern(fromRuleLine: trimmed) else { continue }
            if trimmed.contains("manage=off") {
                if app != ".*" { policy.neverTileApps.append(app) }
            } else if trimmed.contains("manage=on") {
                policy.alwaysTileApps.append(app)
            }
        }

        policy.neverTileApps = Array(Set(policy.neverTileApps)).sorted()
        policy.alwaysTileApps = Array(Set(policy.alwaysTileApps)).sorted()
        return policy
    }

    private func loadConfigDocumentSync() throws -> YabaiConfigDocumentState {
        let path = yabaircPath()
        let fileExists = FileManager.default.fileExists(atPath: path)
        let content = fileExists ? (try readTextFile(path: path)) : ""
        let extracted = try extractManagedSection(from: content)
        let managedBody = extracted?.body ?? renderManagedBody(for: .default)
        return YabaiConfigDocumentState(
            filePath: path,
            fileExists: fileExists,
            fullContent: content,
            managedSectionBody: managedBody,
            hasManagedSection: extracted != nil,
            backups: listBackups(),
            policy: parsePolicy(fromManagedBody: managedBody)
        )
    }

    private func saveWindowBehaviorPolicySync(_ policy: ManagedWindowBehaviorPolicy) throws -> YabaiConfigSaveResult {
        let state = try loadConfigDocumentSync()
        let body = renderManagedBody(for: policy)
        let updated = try applyManagedSection(body: body, to: state.fullContent)
        let path = state.filePath
        try ensureParentDirectoryExists(forFile: path)

        let previousBackup: ConfigBackupInfo?
        if state.fileExists {
            previousBackup = try createBackup(for: path)
        } else {
            previousBackup = nil
        }

        do {
            try writeAtomically(updated, to: path)
        } catch {
            throw YabaiRulesConfigServiceError.io("Failed to write yabairc: \(error.localizedDescription)")
        }

        return YabaiConfigSaveResult(
            filePath: path,
            backups: listBackups(),
            previousBackup: previousBackup,
            wasInsert: !state.hasManagedSection
        )
    }

    private func restoreBackupSync(path backupPath: String) throws -> YabaiConfigRestoreResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupPath) else { throw YabaiRulesConfigServiceError.backupNotFound }
        let destination = yabaircPath()
        try ensureParentDirectoryExists(forFile: destination)

        let preRestoreBackup: ConfigBackupInfo?
        if fm.fileExists(atPath: destination) {
            preRestoreBackup = try createBackup(for: destination)
        } else {
            preRestoreBackup = nil
        }

        let restored = try backupInfo(for: backupPath)
        do {
            let content = try readTextFile(path: backupPath)
            try writeAtomically(content, to: destination)
        } catch {
            throw YabaiRulesConfigServiceError.io("Failed to restore backup: \(error.localizedDescription)")
        }

        return YabaiConfigRestoreResult(
            filePath: destination,
            backups: listBackups(),
            restoredBackup: restored,
            preRestoreBackup: preRestoreBackup
        )
    }

    private func applyManagedSection(body: String, to original: String) throws -> String {
        let normalizedBlock = renderManagedBlock(body: body)
        if let extracted = try extractManagedSection(from: original) {
            var updated = original
            updated.replaceSubrange(extracted.range, with: normalizedBlock)
            return updated
        }
        if original.isEmpty { return normalizedBlock }
        var updated = original
        if !updated.hasSuffix("\n") { updated.append("\n") }
        updated.append("\n")
        updated.append(normalizedBlock)
        return updated
    }

    private func extractManagedSection(from content: String) throws -> (body: String, range: Range<String.Index>)? {
        guard let beginRange = content.range(of: beginMarker) else {
            if content.range(of: endMarker) != nil { throw YabaiRulesConfigServiceError.malformedManagedMarkers }
            return nil
        }
        guard let endRange = content.range(of: endMarker), beginRange.lowerBound < endRange.lowerBound else {
            throw YabaiRulesConfigServiceError.malformedManagedMarkers
        }

        let lineStart = content[..<beginRange.lowerBound].lastIndex(of: "\n").map { content.index(after: $0) } ?? content.startIndex
        let lineEnd: String.Index = content[endRange.upperBound...].firstIndex(of: "\n").map { content.index(after: $0) } ?? content.endIndex
        let managedRange = lineStart..<lineEnd
        var body = String(content[beginRange.upperBound..<endRange.lowerBound])
        if body.hasPrefix("\n") { body.removeFirst() }
        if body.hasSuffix("\n") { body.removeLast() }
        return (body, managedRange)
    }

    private func renderManagedBlock(body: String) -> String {
        let trimmedBody = body.trimmingCharacters(in: .newlines)
        return """
        \(beginMarker)
        \(trimmedBody)
        \(endMarker)

        """
    }

    private func parseAppPattern(fromRuleLine line: String) -> String? {
        guard let appRange = line.range(of: #"app=""#) else { return nil }
        let start = appRange.upperBound
        guard let end = line[start...].firstIndex(of: "\"") else { return nil }
        return unescapeRegex(String(line[start..<end]))
    }

    private func normalizeAppName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func ruleLabels(for policy: ManagedWindowBehaviorPolicy) -> Set<String> {
        var labels = Set<String>()
        for app in policy.alwaysTileApps {
            let trimmed = normalizeAppName(app)
            if !trimmed.isEmpty { labels.insert(ruleLabel(prefix: "tp_always", appName: trimmed)) }
        }
        for app in policy.neverTileApps {
            let trimmed = normalizeAppName(app)
            if !trimmed.isEmpty { labels.insert(ruleLabel(prefix: "tp_never", appName: trimmed)) }
        }
        if policy.manualTilingModeEnabled {
            labels.insert("tp_manual_tiling_default")
        }
        return labels
    }

    private func escapeRegex(_ string: String) -> String {
        NSRegularExpression.escapedPattern(for: string)
    }

    private func unescapeRegex(_ string: String) -> String {
        string.replacingOccurrences(of: #"\"#, with: "")
    }

    private func ruleLabel(prefix: String, appName: String) -> String {
        let lower = appName.lowercased()
        let sanitized = lower.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        var slug = String(sanitized)
        while slug.contains("__") {
            slug = slug.replacingOccurrences(of: "__", with: "_")
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if slug.isEmpty { slug = "app" }
        return "\(prefix)_\(slug.prefix(24))_\(shortHash(lower))"
    }

    private func shortHash(_ input: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(hash, radix: 16).prefix(8).description
    }

    private func createBackup(for sourcePath: String) throws -> ConfigBackupInfo {
        let backupDir = backupsDirectoryPath()
        try FileManager.default.createDirectory(atPath: backupDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "yabairc-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(6)).bak"
        let dest = (backupDir as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(atPath: sourcePath, toPath: dest)
        } catch {
            throw YabaiRulesConfigServiceError.io("Failed to create backup: \(error.localizedDescription)")
        }
        return try backupInfo(for: dest)
    }

    private func listBackups() -> [ConfigBackupInfo] {
        let backupDir = backupsDirectoryPath()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: backupDir), includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return urls.compactMap { try? backupInfo(for: $0.path) }.sorted { $0.createdAt > $1.createdAt }
    }

    private func backupInfo(for path: String) throws -> ConfigBackupInfo {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return ConfigBackupInfo(id: UUID(), path: path, createdAt: values.contentModificationDate ?? .distantPast, sizeBytes: Int64(values.fileSize ?? 0))
    }

    private func writeAtomically(_ content: String, to path: String) throws {
        let destinationURL = URL(fileURLWithPath: path)
        let tempURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            if FileManager.default.fileExists(atPath: path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private func ensureParentDirectoryExists(forFile path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        } catch {
            throw YabaiRulesConfigServiceError.io("Failed to create config directory: \(error.localizedDescription)")
        }
    }

    private func readTextFile(path: String) throws -> String {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw YabaiRulesConfigServiceError.io("Failed to read file: \(error.localizedDescription)")
        }
    }

    private func yabaircPath() -> String {
        NSString(string: "~/.config/yabai/yabairc").expandingTildeInPath
    }

    private func backupsDirectoryPath() -> String {
        NSString(string: "~/.config/tilepilot/backups/yabairc").expandingTildeInPath
    }
}
