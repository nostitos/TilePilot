import Foundation

final class ReleaseDefaultsService: @unchecked Sendable {
    static let currentProfileVersion = "v0.2.9-defaults.1"

    private let fileManager = FileManager.default

    func currentProfile() -> ReleaseDefaultsProfile {
        ReleaseDefaultsProfile(
            profileVersion: Self.currentProfileVersion,
            userState: ReleaseDefaultsUserState(
                pinnedFeatureControlIDs: [
                    "app.keep-on-top-when-floating",
                    "screen.set-floating-all-visible",
                    "screen.grid-auto-tiled",
                    "screen.grid-floating",
                    "screen.rotate-layout",
                    "screen.balance-current-desktop",
                    "screen.bring-floating-front",
                ],
                pinnedDirectionalGroupIDs: [],
                shortcutsCustomOrderIDs: [
                    "directional.moveWindow",
                    "directional.resizeWindow",
                    "directional.focusWindow",
                ],
                showWindowBadgeOverlay: true,
                showWindowOutlineOverlay: true,
                windowOutlineOverlayBaseWidth: 1.0,
                raiseOnFloatToggleEnabled: true,
                appForegroundPolicyByName: [:],
                performanceSettings: .responsive
            ),
            configState: ReleaseDefaultsConfigState(
                managedSkhdSectionBody: defaultManagedSkhdSectionBody(),
                windowBehaviorPolicy: ManagedWindowBehaviorPolicy(
                    manualTilingModeEnabled: true,
                    hoverFocusMode: .off,
                    mouseFollowsFocusEnabled: false,
                    outerPadding: 0,
                    windowGap: 0,
                    mouseModifier: .alt,
                    mouseAction1: .move,
                    mouseAction2: .resize,
                    mouseDropAction: .swap,
                    neverTileApps: [],
                    alwaysTileApps: []
                )
            )
        )
    }

    func writeProfileSnapshotToDisk(_ profile: ReleaseDefaultsProfile) throws {
        let directory = defaultsDirectoryURL()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(profile)
        let versionFile = directory.appendingPathComponent("release-defaults-\(profile.profileVersion).json")
        let currentAlias = directory.appendingPathComponent("release-defaults-current.json")
        try data.write(to: versionFile, options: .atomic)
        try data.write(to: currentAlias, options: .atomic)
    }

    func loadLastSnapshotIfPresent() -> ReleaseDefaultsProfile? {
        let currentAlias = defaultsDirectoryURL().appendingPathComponent("release-defaults-current.json")
        guard fileManager.fileExists(atPath: currentAlias.path) else { return nil }
        guard let data = try? Data(contentsOf: currentAlias) else { return nil }
        return try? JSONDecoder().decode(ReleaseDefaultsProfile.self, from: data)
    }

    func hasLegacyUserDefaultsFootprint(_ defaults: UserDefaults = .standard) -> Bool {
        let keys = [
            "TilePilot.pinnedShortcutKeys",
            "TilePilot.pinnedDirectionalGroupIDs",
            "TilePilot.pinnedFeatureControlIDs",
            "TilePilot.shortcutsCustomOrderIDs",
            "TilePilot.showWindowBadgeOverlay",
            "TilePilot.showWindowOutlineOverlay",
            "TilePilot.windowOutlineOverlayBaseWidth",
            "TilePilot.raiseOnFloatToggle",
            "TilePilot.appForegroundPolicyByName",
            "TilePilot.performanceHideMinimizedHelperWindowsInMaps",
        ]
        return keys.contains { defaults.object(forKey: $0) != nil }
    }

    private func defaultManagedSkhdSectionBody() -> String {
        """
        # Managed by TilePilot. Unknown lines outside this block are preserved.
        # Release default shortcuts:
        # TILEPILOT_FEATURE screen.set-floating-all-visible
        ctrl + shift + alt - d : \(featureCommand("screen.set-floating-all-visible"))
        # TILEPILOT_FEATURE screen.set-tiled-all-visible
        ctrl + shift + alt - e : \(featureCommand("screen.set-tiled-all-visible"))
        # TILEPILOT_FEATURE screen.grid-floating
        ctrl + shift + alt - p : \(featureCommand("screen.grid-floating"))
        # TILEPILOT_FEATURE screen.grid-auto-tiled
        ctrl + shift + alt - o : \(featureCommand("screen.grid-auto-tiled"))
        # TILEPILOT_FEATURE screen.rotate-layout
        shift + alt - r : \(featureCommand("screen.rotate-layout"))
        # TILEPILOT_FEATURE screen.layout-bsp-balance
        ctrl + shift + alt - g : yabai -m space --layout bsp; yabai -m space --balance
        # TILEPILOT_FEATURE screen.balance-current-desktop
        alt - 0 : yabai -m space --balance
        # TILEPILOT_FEATURE action.toggle-float
        ctrl + shift + alt - ~ : yabai -m window --toggle float
        """
    }

    private func featureCommand(_ featureID: String) -> String {
        "/usr/bin/open -g \"tilepilot://feature/\(featureID)\""
    }

    private func defaultsDirectoryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TilePilot/Defaults", isDirectory: true)
    }
}
