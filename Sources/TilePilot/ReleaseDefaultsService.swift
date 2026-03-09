import Foundation

final class ReleaseDefaultsService: @unchecked Sendable {
    static let currentProfileVersion = "v0.2.2-defaults.1"

    private let fileManager = FileManager.default

    func currentProfile() -> ReleaseDefaultsProfile {
        ReleaseDefaultsProfile(
            profileVersion: Self.currentProfileVersion,
            userState: ReleaseDefaultsUserState(
                pinnedFeatureControlIDs: [
                    "screen.set-floating-all-visible",
                    "screen.set-tiled-all-visible",
                    "screen.grid-floating",
                    "screen.grid-auto-tiled",
                    "screen.balance-current-desktop",
                ],
                pinnedDirectionalGroupIDs: [],
                shortcutsCustomOrderIDs: [],
                showWindowBadgeOverlay: true,
                showWindowOutlineOverlay: false,
                raiseOnFloatToggleEnabled: true,
                appForegroundPolicyByName: [:],
                performanceSettings: .balanced
            ),
            configState: ReleaseDefaultsConfigState(
                managedSkhdSectionBody: defaultManagedSkhdSectionBody(),
                windowBehaviorPolicy: .default
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
            "TilePilot.raiseOnFloatToggle",
            "TilePilot.appForegroundPolicyByName",
            "TilePilot.initialSetupLandingShown",
        ]
        return keys.contains { defaults.object(forKey: $0) != nil }
    }

    private func defaultManagedSkhdSectionBody() -> String {
        """
        # Managed by TilePilot. Unknown lines outside this block are preserved.
        # Release default shortcuts:
        # TILEPILOT_FEATURE screen.set-floating-all-visible
        ctrl + shift + alt - d : ~/.config/yabai/scripts/disable-tiling-all-visible.sh
        # TILEPILOT_FEATURE screen.set-tiled-all-visible
        ctrl + shift + alt - e : ~/.config/yabai/scripts/enable-tiling-all-visible.sh
        # TILEPILOT_FEATURE screen.grid-floating
        ctrl + shift + alt - p : ~/.config/yabai/scripts/grid-tiling-floating.sh
        # TILEPILOT_FEATURE screen.grid-auto-tiled
        ctrl + shift + alt - o : ~/.config/yabai/scripts/rebuild-balanced-tile-layout.sh
        # TILEPILOT_FEATURE screen.layout-bsp-balance
        ctrl + shift + alt - g : yabai -m space --layout bsp; yabai -m space --balance
        # TILEPILOT_FEATURE screen.balance-current-desktop
        alt - 0 : yabai -m space --balance
        # TILEPILOT_FEATURE action.toggle-float
        ctrl + shift + alt - ~ : yabai -m window --toggle float
        """
    }

    private func defaultsDirectoryURL() -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TilePilot/Defaults", isDirectory: true)
    }
}
