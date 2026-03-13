import Foundation

@MainActor
extension AppModel {
    struct FeatureDefinition: Sendable {
        let id: FeatureControlID
        let group: UnifiedControlGroup
        let title: String
        let description: String
        let backend: FeatureExecutionBackend
        let capabilityGate: FeatureCapabilityGate
        let defaultCombo: String?
        let commandMatchers: [String]
        let matchAllCommandMatchers: Bool
        let preferredCommand: String?
        let actionID: TilePilotActionID?
        let isExperimental: Bool
    }

    func tilePilotFeatureURL(_ featureID: FeatureControlID) -> String {
        "tilepilot://feature/\(featureID.rawValue)"
    }

    func tilePilotFeatureCommand(_ featureID: FeatureControlID) -> String {
        "/usr/bin/open -g \"\(tilePilotFeatureURL(featureID))\""
    }

    var featureDefinitions: [FeatureDefinition] {
        [
            FeatureDefinition(
                id: "screen.set-floating-all-visible",
                group: .tilingLayout,
                title: "All Windows → Floating",
                description: "Sets windows to floating. Applies to windows visible on the current desktop.",
                backend: .scriptPath,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "ctrl + shift + alt - d",
                commandMatchers: ["/.config/yabai/scripts/disable-tiling-all-visible.sh"],
                matchAllCommandMatchers: false,
                preferredCommand: "~/.config/yabai/scripts/disable-tiling-all-visible.sh",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.set-tiled-all-visible",
                group: .tilingLayout,
                title: "All Windows → Tiled",
                description: "Sets windows to tiled. Applies to windows visible on the current desktop.",
                backend: .scriptPath,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "ctrl + shift + alt - e",
                commandMatchers: ["/.config/yabai/scripts/enable-tiling-all-visible.sh"],
                matchAllCommandMatchers: false,
                preferredCommand: "~/.config/yabai/scripts/enable-tiling-all-visible.sh",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.bring-floating-front",
                group: .tilingLayout,
                title: "Bring Floating Windows to Front",
                description: "One-time action: raises all floating windows on the current desktop.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: nil,
                commandMatchers: [
                    tilePilotFeatureURL("screen.bring-floating-front"),
                    "tilepilot:/feature/screen.bring-floating-front",
                ],
                matchAllCommandMatchers: false,
                preferredCommand: "/usr/bin/open -g \"tilepilot://feature/screen.bring-floating-front\"",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.current-desktop-tiling-on",
                group: .tilingLayout,
                title: "Desktop Tiling On",
                description: "Turns tiling on for the current desktop.",
                backend: .shortcutCommand,
                capabilityGate: .yabaiRuntime,
                defaultCombo: nil,
                commandMatchers: ["yabai -m space --layout bsp"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m space --layout bsp",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.current-desktop-tiling-off",
                group: .tilingLayout,
                title: "Desktop Tiling Off",
                description: "Turns tiling off for the current desktop (floating layout).",
                backend: .shortcutCommand,
                capabilityGate: .yabaiRuntime,
                defaultCombo: nil,
                commandMatchers: ["yabai -m space --layout float"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m space --layout float",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.grid-floating",
                group: .tilingLayout,
                title: "Grid Tiling",
                description: "Packs visible windows into a grid and keeps them floating.",
                backend: .scriptPath,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "ctrl + shift + alt - p",
                commandMatchers: ["/.config/yabai/scripts/grid-tiling-floating.sh", "/.config/yabai/scripts/grid-pack-toggle.sh"],
                matchAllCommandMatchers: false,
                preferredCommand: "~/.config/yabai/scripts/grid-tiling-floating.sh",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.grid-auto-tiled",
                group: .tilingLayout,
                title: "Rebuild Tile Layout",
                description: "Rebuilds the current desktop into a more even tiled BSP layout.",
                backend: .scriptPath,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "ctrl + shift + alt - o",
                commandMatchers: [
                    "/.config/yabai/scripts/rebuild-balanced-tile-layout.sh",
                    "/.config/yabai/scripts/grid-tiling-auto-tiled.sh"
                ],
                matchAllCommandMatchers: false,
                preferredCommand: "~/.config/yabai/scripts/rebuild-balanced-tile-layout.sh",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.layout-bsp-balance",
                group: .tilingLayout,
                title: "Set Tile Layout",
                description: "Switches current desktop to tile layout and rebalances.",
                backend: .shortcutCommand,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "ctrl + shift + alt - g",
                commandMatchers: ["yabai -m space --layout bsp", "yabai -m space --balance"],
                matchAllCommandMatchers: true,
                preferredCommand: "yabai -m space --layout bsp; yabai -m space --balance",
                actionID: .layoutBSPAndBalance,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.balance-current-desktop",
                group: .tilingLayout,
                title: "Balance Tiles",
                description: "Rebalances tiled windows without changing layout mode.",
                backend: .shortcutCommand,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "alt - 0",
                commandMatchers: ["yabai -m space --balance"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m space --balance",
                actionID: .balanceSpace,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "action.layout-stack",
                group: .tilingLayout,
                title: "Stack Layout",
                description: "Sets stack layout on the current desktop.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "shift + alt - v",
                commandMatchers: ["yabai -m space --layout stack"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m space --layout stack",
                actionID: .layoutStack,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "screen.rotate-layout",
                group: .tilingLayout,
                title: "Rotate Layout",
                description: "Rotates layout by 90 degrees on the current desktop.",
                backend: .shortcutCommand,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "shift + alt - r",
                commandMatchers: ["yabai -m space --rotate"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m space --rotate 90",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "action.toggle-float",
                group: .tilingLayout,
                title: "Toggle Floating/Tiled",
                description: "Toggles the focused window between floating and tiled.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "ctrl + shift + alt - ~",
                commandMatchers: ["yabai -m window --toggle float"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m window --toggle float",
                actionID: .toggleFloat,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "app.open-tilepilot",
                group: .apps,
                title: "Open TilePilot",
                description: "Brings TilePilot to the front so you can access the mini-map fast.",
                backend: .shortcutCommand,
                capabilityGate: .none,
                defaultCombo: "ctrl + shift + alt - return",
                commandMatchers: [
                    "open -a tilepilot",
                    "open -a \"tilepilot\"",
                    "/contents/macos/tilepilot",
                ],
                matchAllCommandMatchers: false,
                preferredCommand: "/usr/bin/open -a \"TilePilot\"",
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "app.open-megamap",
                group: .desktops,
                title: "Open Megamap",
                description: "Opens the large screenshot-based view of all desktops.",
                backend: .tilePilotAction,
                capabilityGate: .none,
                defaultCombo: nil,
                commandMatchers: [tilePilotFeatureURL("app.open-megamap")],
                matchAllCommandMatchers: false,
                preferredCommand: tilePilotFeatureCommand("app.open-megamap"),
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "app.refresh-megamap",
                group: .desktops,
                title: "Refresh Megamap",
                description: "Visibly sweeps desktops and captures fresh Megamap screenshots.",
                backend: .tilePilotAction,
                capabilityGate: .none,
                defaultCombo: nil,
                commandMatchers: [tilePilotFeatureURL("app.refresh-megamap")],
                matchAllCommandMatchers: false,
                preferredCommand: tilePilotFeatureCommand("app.refresh-megamap"),
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "app.keep-on-top-when-floating",
                group: .apps,
                title: "Keep App on Top",
                description: "Toggles keep-on-top for the focused app (or the badge app from a window badge).",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: nil,
                commandMatchers: [tilePilotFeatureURL("app.keep-on-top-when-floating")],
                matchAllCommandMatchers: false,
                preferredCommand: tilePilotFeatureCommand("app.keep-on-top-when-floating"),
                actionID: nil,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "action.focus-left",
                group: .focus,
                title: "Focus Left",
                description: "Moves focus to the window on the left.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "alt - j",
                commandMatchers: ["yabai -m window --focus west"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m window --focus west",
                actionID: .focusWest,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "action.focus-right",
                group: .focus,
                title: "Focus Right",
                description: "Moves focus to the window on the right.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "alt - l",
                commandMatchers: ["yabai -m window --focus east"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m window --focus east",
                actionID: .focusEast,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "action.focus-up",
                group: .focus,
                title: "Focus Up",
                description: "Moves focus to the window above.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "alt - i",
                commandMatchers: ["yabai -m window --focus north"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m window --focus north",
                actionID: .focusNorth,
                isExperimental: false
            ),
            FeatureDefinition(
                id: "action.focus-down",
                group: .focus,
                title: "Focus Down",
                description: "Moves focus to the window below.",
                backend: .tilePilotAction,
                capabilityGate: .yabaiRuntime,
                defaultCombo: "alt - k",
                commandMatchers: ["yabai -m window --focus south"],
                matchAllCommandMatchers: false,
                preferredCommand: "yabai -m window --focus south",
                actionID: .focusSouth,
                isExperimental: false
            ),
        ]
    }

    func featureDefinition(for entry: ShortcutEntry) -> FeatureDefinition? {
        let command = normalizedFeatureMatchCommand(entry.command.lowercased())
        return featureDefinitions.first { definition in
            guard !definition.commandMatchers.isEmpty else { return false }
            if definition.matchAllCommandMatchers {
                return definition.commandMatchers.allSatisfy { command.contains($0) }
            }
            return definition.commandMatchers.contains(where: { command.contains($0) })
        }
    }

    func normalizedFeatureMatchCommand(_ raw: String) -> String {
        FeatureCommandNormalizer.normalize(raw)
    }
}
