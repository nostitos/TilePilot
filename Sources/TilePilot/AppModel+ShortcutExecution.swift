import Foundation

@MainActor
extension AppModel {
func runFeatureControl(_ featureID: FeatureControlID, source: FeatureRunSource, appContext: String? = nil) {
    guard let row = featureControlRow(forID: featureID) else {
        lastErrorMessage = "Feature is no longer available."
        lastActionMessage = nil
        return
    }
    if let disabledReason = row.disabledReason {
        lastErrorMessage = disabledReason
        lastActionMessage = nil
        return
    }
    if featureID.rawValue == "app.keep-on-top-when-floating" {
        let selectedApp = appContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusedApp = focusedAppName
        let candidateApps = [selectedApp ?? "", focusedApp ?? ""]
        guard let appName = candidateApps.first(where: { !$0.isEmpty }) else {
            lastErrorMessage = "No app available to apply keep-on-top."
            lastActionMessage = nil
            return
        }
        toggleKeepFrontWhenFloating(for: appName)
        return
    }
    if featureID.rawValue == "app.never-auto-tile" {
        let selectedApp = appContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        let focusedApp = focusedAppName
        let candidateApps = [selectedApp ?? "", focusedApp ?? ""]
        guard let appName = candidateApps.first(where: { !$0.isEmpty }) else {
            lastErrorMessage = "No app available to mark Never Auto-Tile."
            lastActionMessage = nil
            return
        }
        toggleNeverAutoTile(for: appName)
        return
    }
    if featureID.rawValue == "screen.bring-floating-front" {
        bringFloatingWindowsToFrontCurrentDesktop()
        return
    }
    if featureID.rawValue == "screen.set-floating-all-visible" {
        setVisibleWindowsFloatingCurrentDesktop()
        return
    }
    if featureID.rawValue == "screen.set-tiled-all-visible" {
        setVisibleWindowsTiledCurrentDesktop()
        return
    }
    if featureID.rawValue == "screen.grid-floating" {
        applyFloatingGridToCurrentDesktop()
        return
    }
    if featureID.rawValue == "screen.grid-auto-tiled" {
        rebuildTileLayoutCurrentDesktop()
        return
    }
    if featureID.rawValue == "app.open-megamap" {
        presentMegamap()
        return
    }
    if featureID.rawValue == "app.run-guided-setup" {
        presentSetupGuide()
        return
    }
    if featureID.rawValue == "app.refresh-megamap" {
        refreshMegamap()
        return
    }
    if let entry = row.shortcutEntry {
        runShortcut(entry)
        return
    }
    if let actionID = row.actionID {
        performTilePilotAction(actionID)
        return
    }
    if let command = row.preferredCommand {
        runShortcutCommand(command, shortcutLabel: row.title)
        return
    }
    lastErrorMessage = "No shortcut assigned yet. Use Set Shortcut in Shortcuts."
    lastActionMessage = nil
}

func assignShortcut(combo: String, to featureID: FeatureControlID) {
    guard let definition = featureDefinitions.first(where: { $0.id == featureID }) else {
        lastErrorMessage = "Unknown feature."
        lastActionMessage = nil
        return
    }
    guard let preferredCommand = definition.preferredCommand else {
        lastErrorMessage = "This feature has no assignable command yet."
        lastActionMessage = nil
        return
    }
    let normalizedTarget = normalizedShortcutCombo(combo)
    guard !normalizedTarget.isEmpty else {
        lastErrorMessage = "Shortcut cannot be empty."
        lastActionMessage = nil
        return
    }

    if let conflict = shortcutEntries.first(where: {
        normalizedShortcutCombo($0.combo) == normalizedTarget &&
            (featureDefinition(for: $0)?.id != featureID)
    }) {
        let conflictName = featureDefinition(for: conflict)?.title ?? shortcutTitle(conflict)
        let suggestions = suggestShortcutAlternatives(for: combo)
        let suggestionText = suggestions.isEmpty ? "" : " Try: \(suggestions.joined(separator: ", "))."
        lastErrorMessage = "Shortcut already used by \(conflictName).\(suggestionText)"
        lastActionMessage = nil
        return
    }

    let command = NSString(string: preferredCommand).expandingTildeInPath
    upsertManagedFeatureShortcut(featureID: featureID, combo: combo, command: command)
    saveManagedConfigSection()
}

func assignShortcut(combo: String, to entry: ShortcutEntry) {
    let normalizedTarget = normalizedShortcutCombo(combo)
    guard !normalizedTarget.isEmpty else {
        lastErrorMessage = "Shortcut cannot be empty."
        lastActionMessage = nil
        return
    }

    if let conflict = shortcutEntries.first(where: {
        normalizedShortcutCombo($0.combo) == normalizedTarget && $0.stableKey != entry.stableKey
    }) {
        let conflictName = featureDefinition(for: conflict)?.title ?? shortcutTitle(conflict)
        let suggestions = suggestShortcutAlternatives(for: combo)
        let suggestionText = suggestions.isEmpty ? "" : " Try: \(suggestions.joined(separator: ", "))."
        lastErrorMessage = "Shortcut already used by \(conflictName).\(suggestionText)"
        lastActionMessage = nil
        return
    }

    let expandedPath = NSString(string: entry.sourceFile).expandingTildeInPath
    Task { [weak self] in
        guard let self else { return }
        do {
            let document = try await self.configFilesService.loadDocument(path: expandedPath)
            var lines = document.content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
            let lineIndex = max(0, entry.sourceLine - 1)
            guard lineIndex < lines.count else {
                await MainActor.run {
                    self.lastErrorMessage = "Could not update shortcut: source line \(entry.sourceLine) is out of range."
                    self.lastActionMessage = nil
                }
                return
            }

            let commandPart = self.shortcutCommandSegment(from: lines[lineIndex], fallback: entry.command)
            lines[lineIndex] = "\(combo) : \(commandPart)"
            var rewritten = lines.joined(separator: "\n")
            if document.content.hasSuffix("\n") {
                rewritten += "\n"
            }
            _ = try await self.configFilesService.saveFile(path: expandedPath, content: rewritten)
            await MainActor.run {
                self.lastActionMessage = "Shortcut updated for \(self.shortcutTitle(entry))."
                self.lastErrorMessage = nil
            }
            await self.refreshShortcuts()
        } catch {
            await MainActor.run {
                self.lastErrorMessage = "Failed to update shortcut: \(error.localizedDescription)"
                self.lastActionMessage = nil
            }
        }
    }
}

func removeShortcut(for featureID: FeatureControlID) {
    removeManagedFeatureShortcut(featureID: featureID)
    saveManagedConfigSection()
}

func suggestShortcutAlternatives(for combo: String) -> [String] {
    let used = Set(shortcutEntries.map { normalizedShortcutCombo($0.combo) })
    let pool = [
        "ctrl + shift + alt - d",
        "ctrl + shift + alt - e",
        "ctrl + shift + alt - p",
        "ctrl + shift + alt - o",
        "ctrl + shift + alt - g",
        "ctrl + shift + alt - f",
        "ctrl + shift + alt - b",
        "ctrl + shift + alt - n",
        "ctrl + shift + alt - m",
        "shift + alt - b",
        "shift + alt - v",
        "alt - 0",
    ]
    let normalizedCurrent = normalizedShortcutCombo(combo)
    return pool.filter { candidate in
        let normalizedCandidate = normalizedShortcutCombo(candidate)
        return normalizedCandidate != normalizedCurrent && !used.contains(normalizedCandidate)
    }
    .prefix(4)
    .map { $0 }
}

func featureDisabledReason(for gate: FeatureCapabilityGate) -> String? {
    switch gate {
    case .none:
        return nil
    case .yabaiRuntime:
        return canRunYabaiRuntimeCommands ? nil : (yabaiRuntimeControlDisabledReason ?? "yabai runtime controls are unavailable.")
    case .scriptingAddition:
        return "Not supported by TilePilot."
    }
}

func normalizedShortcutCombo(_ combo: String) -> String {
    combo
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s*\\+\\s*", with: " + ", options: .regularExpression)
        .replacingOccurrences(of: "\\s*-\\s*", with: " - ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func shortcutCommandSegment(from line: String, fallback: String) -> String {
    guard let colonIndex = line.firstIndex(of: ":") else { return fallback }
    let raw = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
    return raw.isEmpty ? fallback : raw
}

private func upsertManagedFeatureShortcut(featureID: FeatureControlID, combo: String, command: String) {
    let marker = managedFeatureMarkerPrefix + featureID.rawValue
    let shortcutLine = "\(combo) : \(command)"
    var lines = managedConfigDraft.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)

    if let markerIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker }) {
        if markerIndex + 1 < lines.count, lines[markerIndex + 1].contains(":") {
            lines[markerIndex + 1] = shortcutLine
        } else {
            lines.insert(shortcutLine, at: markerIndex + 1)
        }
    } else {
        if !lines.isEmpty, !lines.last!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
        }
        lines.append(marker)
        lines.append(shortcutLine)
    }
    managedConfigDraft = lines.joined(separator: "\n")
    recomputeConfigDiffPreview()
}

private func removeManagedFeatureShortcut(featureID: FeatureControlID) {
    let marker = managedFeatureMarkerPrefix + featureID.rawValue
    var lines = managedConfigDraft.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    var index = 0
    while index < lines.count {
        if lines[index].trimmingCharacters(in: .whitespaces) == marker {
            lines.remove(at: index)
            if index < lines.count, lines[index].contains(":") {
                lines.remove(at: index)
            }
            if index < lines.count, lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.remove(at: index)
            }
            continue
        }
        index += 1
    }
    managedConfigDraft = lines.joined(separator: "\n")
    recomputeConfigDiffPreview()
}

}
