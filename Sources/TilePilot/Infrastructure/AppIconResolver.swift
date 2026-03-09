import AppKit
import Foundation

@MainActor
final class AppIconResolver {
    static let shared = AppIconResolver()

    private let fileManager = FileManager.default
    private var urlCache: [String: URL?] = [:]
    private var baseIconCache: [String: NSImage?] = [:]
    private var sizedIconCache: [String: NSImage?] = [:]

    private var searchDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
        ]
    }

    func icon(forAppNamed appName: String, size: CGFloat? = nil) -> NSImage? {
        let key = normalizedAppName(appName)
        guard !key.isEmpty else { return nil }

        let baseIcon: NSImage?
        if let cached = baseIconCache[key] {
            baseIcon = cached
        } else {
            let resolved = resolveIcon(forNormalizedAppName: key)
            baseIconCache[key] = resolved
            baseIcon = resolved
        }

        guard let baseIcon else { return nil }
        guard let size else { return baseIcon }
        let sizeKey = "\(key)|\(Int(size.rounded()))"
        if let cached = sizedIconCache[sizeKey] {
            return cached
        }

        let resized = (baseIcon.copy() as? NSImage) ?? baseIcon
        resized.size = NSSize(width: size, height: size)
        sizedIconCache[sizeKey] = resized
        return resized
    }

    private func resolveIcon(forNormalizedAppName appName: String) -> NSImage? {
        if let runningIcon = NSWorkspace.shared.runningApplications
            .first(where: { normalizedAppName($0.localizedName ?? "") == appName })?.icon {
            return runningIcon
        }

        guard let appURL = resolveAppURL(forNormalizedAppName: appName) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func resolveAppURL(forNormalizedAppName appName: String) -> URL? {
        if let cached = urlCache[appName] {
            return cached
        }

        let exactName = "\(appName).app"

        for directory in searchDirectories {
            let directURL = directory.appendingPathComponent(exactName, isDirectory: true)
            if fileManager.fileExists(atPath: directURL.path) {
                urlCache[appName] = directURL
                return directURL
            }
        }

        for directory in searchDirectories where fileManager.fileExists(atPath: directory.path) {
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: options
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                let candidateName = normalizedAppName(url.deletingPathExtension().lastPathComponent)
                if candidateName == appName {
                    urlCache[appName] = url
                    return url
                }
            }
        }

        urlCache[appName] = nil
        return nil
    }

    private func normalizedAppName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
