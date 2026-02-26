import AppKit
import CoreGraphics
import Foundation

struct LiveStatePollResult: Sendable {
    let timestamp: Date
    let yabaiDisplays: [DisplayState]?
    let yabaiSpaces: [SpaceState]?
    let yabaiWindows: [WindowState]?
    let fallbackDisplays: [FallbackDisplayCount]
    let yabaiWindowTotal: Int?
    let fallbackWindowTotal: Int?
    let errorMessage: String?
}

final class YabaiStateService: @unchecked Sendable {
    private let runner = CommandRunner()

    func pollLiveState() async -> LiveStatePollResult {
        async let displaysTask = runner.run(.init("/usr/bin/env", ["yabai", "-m", "query", "--displays"], timeout: 1.5))
        async let spacesTask = runner.run(.init("/usr/bin/env", ["yabai", "-m", "query", "--spaces"], timeout: 1.5))
        async let windowsTask = runner.run(.init("/usr/bin/env", ["yabai", "-m", "query", "--windows"], timeout: 1.5))
        async let fallbackTask = fallbackDisplayCounts()

        let timestamp = Date()
        let displaysResult = await displaysTask
        let spacesResult = await spacesTask
        let windowsResult = await windowsTask
        let fallbackDisplays = await fallbackTask

        let fallbackTotal = fallbackDisplays.reduce(0) { $0 + $1.windowCount }

        guard displaysResult.isSuccess, spacesResult.isSuccess, windowsResult.isSuccess else {
            let rawMessage = firstNonEmpty([
                windowsResult.stderr,
                spacesResult.stderr,
                displaysResult.stderr,
                windowsResult.stdout,
                spacesResult.stdout,
                displaysResult.stdout,
            ]) ?? "yabai query failed"
            let message = userFacingLiveStateError(from: rawMessage)

            return LiveStatePollResult(
                timestamp: timestamp,
                yabaiDisplays: nil,
                yabaiSpaces: nil,
                yabaiWindows: nil,
                fallbackDisplays: fallbackDisplays,
                yabaiWindowTotal: nil,
                fallbackWindowTotal: fallbackDisplays.isEmpty ? nil : fallbackTotal,
                errorMessage: trimForUI(message)
            )
        }

        do {
            let parsed = try parseYabaiState(
                displaysJSON: displaysResult.stdout,
                spacesJSON: spacesResult.stdout,
                windowsJSON: windowsResult.stdout,
                timestamp: timestamp
            )

            return LiveStatePollResult(
                timestamp: timestamp,
                yabaiDisplays: parsed.displays,
                yabaiSpaces: parsed.spaces,
                yabaiWindows: parsed.windows,
                fallbackDisplays: fallbackDisplays,
                yabaiWindowTotal: parsed.windows.count,
                fallbackWindowTotal: fallbackDisplays.isEmpty ? nil : fallbackTotal,
                errorMessage: nil
            )
        } catch {
            return LiveStatePollResult(
                timestamp: timestamp,
                yabaiDisplays: nil,
                yabaiSpaces: nil,
                yabaiWindows: nil,
                fallbackDisplays: fallbackDisplays,
                yabaiWindowTotal: nil,
                fallbackWindowTotal: fallbackDisplays.isEmpty ? nil : fallbackTotal,
                errorMessage: trimForUI("Failed to parse yabai JSON: \(error.localizedDescription)")
            )
        }
    }

    private func parseYabaiState(
        displaysJSON: String,
        spacesJSON: String,
        windowsJSON: String,
        timestamp: Date
    ) throws -> (displays: [DisplayState], spaces: [SpaceState], windows: [WindowState]) {
        let displayRows = try jsonArray(from: displaysJSON)
        let spaceRows = try jsonArray(from: spacesJSON)
        let windowRows = try jsonArray(from: windowsJSON)

        let windows: [WindowState] = windowRows.compactMap { row in
            guard let id = int(from: row["id"]),
                  let space = int(from: row["space"]),
                  let display = int(from: row["display"]) else {
                return nil
            }

            return WindowState(
                id: id,
                app: string(from: row["app"]) ?? "Unknown",
                space: space,
                display: display,
                floating: bool(from: row["is-floating"]) ?? false,
                title: string(from: row["title"]) ?? "",
                focused: bool(from: row["has-focus"]) ?? false,
                isVisible: bool(from: row["is-visible"]) ?? true,
                isMinimized: bool(from: row["is-minimized"]) ?? false,
                isHidden: bool(from: row["is-hidden"]) ?? false,
                source: .yabai,
                lastUpdatedAt: timestamp
            )
        }
        .sorted { lhs, rhs in
            if lhs.display != rhs.display { return lhs.display < rhs.display }
            if lhs.space != rhs.space { return lhs.space < rhs.space }
            return lhs.id < rhs.id
        }

        let windowCountByDisplay = Dictionary(grouping: windows, by: \.display).mapValues(\.count)
        let windowCountBySpace = Dictionary(grouping: windows, by: \.space).mapValues(\.count)

        let spaces: [SpaceState] = spaceRows.compactMap { row in
            guard let index = int(from: row["index"]),
                  let display = int(from: row["display"]) else {
                return nil
            }
            let declaredWindowsCount = (row["windows"] as? [Any])?.count
            let effectiveCount = windowCountBySpace[index] ?? declaredWindowsCount ?? 0

            return SpaceState(
                index: index,
                label: string(from: row["label"]),
                displayId: display,
                focused: bool(from: row["has-focus"]) ?? false,
                visible: bool(from: row["is-visible"]) ?? false,
                layout: string(from: row["type"]),
                windowCount: effectiveCount,
                source: .yabai,
                lastUpdatedAt: timestamp
            )
        }
        .sorted { $0.index < $1.index }

        let displays: [DisplayState] = displayRows.compactMap { row in
            guard let id = int(from: row["index"]) ?? int(from: row["id"]) else {
                return nil
            }
            let name = "Display \(id)"
            return DisplayState(
                id: id,
                name: name,
                focused: bool(from: row["has-focus"]) ?? false,
                windowCount: windowCountByDisplay[id] ?? 0,
                source: .yabai,
                lastUpdatedAt: timestamp
            )
        }
        .sorted { $0.id < $1.id }

        return (displays, spaces, windows)
    }

    private func jsonArray(from string: String) throws -> [[String: Any]] {
        let data = Data(string.utf8)
        let value = try JSONSerialization.jsonObject(with: data)
        guard let rows = value as? [[String: Any]] else {
            throw NSError(domain: "YabaiStateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected JSON array"])
        }
        return rows
    }

    private func int(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    private func bool(from value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.intValue != 0
        case let string as String:
            switch string.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    private func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func firstNonEmpty(_ values: [String]) -> String? {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func trimForUI(_ string: String, maxLength: Int = 220) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "..."
    }

    private func userFacingLiveStateError(from raw: String) -> String {
        let normalized = raw.lowercased()
        if normalized.contains("env: yabai: no such file or directory") || normalized.contains("not found") {
            return "yabai is not installed yet. Use Setup -> Install Dependencies, then return to Now."
        }
        if normalized.contains("could not connect") || normalized.contains("message socket") {
            return "yabai is installed but not running. Start the yabai service in Setup or use Restart yabai."
        }
        if normalized.contains("permission") && normalized.contains("denied") {
            return "yabai query failed due to permissions. Check setup/health guidance and retry."
        }
        return raw
    }

    private func fallbackDisplayCounts() async -> [FallbackDisplayCount] {
        await MainActor.run {
            let timestamp = Date()
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return [] }

            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

            var countsByScreenIndex = Array(repeating: 0, count: screens.count)

            for info in infoList {
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                if layer != 0 { continue }

                let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
                if alpha <= 0.01 { continue }

                let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
                if ownerName == "Window Server" || ownerName == "Control Center" {
                    continue
                }

                guard let boundsValue = info[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsValue) else {
                    continue
                }

                let area = bounds.width * bounds.height
                if area < 400 {
                    continue
                }

                guard let screenIndex = bestScreenIndex(for: bounds, screens: screens) else {
                    continue
                }
                countsByScreenIndex[screenIndex] += 1
            }

            return screens.enumerated().map { idx, screen in
                let name: String
                if #available(macOS 10.15, *) {
                    name = screen.localizedName
                } else {
                    name = "Display \(idx + 1)"
                }
                return FallbackDisplayCount(
                    id: "\(idx + 1)",
                    name: name,
                    windowCount: countsByScreenIndex[idx],
                    source: .fallback,
                    lastUpdatedAt: timestamp
                )
            }
        }
    }

    private func bestScreenIndex(for rect: CGRect, screens: [NSScreen]) -> Int? {
        var bestIndex: Int?
        var bestArea: CGFloat = 0
        for (index, screen) in screens.enumerated() {
            let intersection = rect.intersection(screen.frame)
            if intersection.isNull || intersection.isEmpty { continue }
            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        return bestIndex
    }
}
