import AppKit
import Foundation

@MainActor
extension AppModel {
    private var currentSnapshotForRuntimeConsumers: LiveStateSnapshot? {
        latestLiveStateSnapshot ?? liveStateSnapshot
    }

    var availableAppNamesFromLiveState: [String] {
        let names = Set((liveStateSnapshot?.windows ?? []).map(\.app).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return names.sorted()
    }

    var appNamesForBehaviorEditor: [String] {
        let names = Set(availableAppNamesFromLiveState)
            .union(windowBehaviorPolicyDraft.neverTileApps)
            .union(windowBehaviorPolicyDraft.alwaysTileApps)
            .union(stagedNeverTileApps)
            .union(stagedAlwaysTileApps)
        return names.sorted()
    }

    var focusedWindowState: WindowState? {
        liveStateSnapshot?.windows.first(where: \.focused)
    }

    func isOverviewExcludedWindow(_ window: WindowState, in snapshot: LiveStateSnapshot) -> Bool {
        if window.app == "zoom.us" {
            guard !window.canResize else { return false }
            let tiny = window.frameW <= 140 || window.frameH <= 60
            guard tiny else { return false }
            let normalizedTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalizedTitle.isEmpty || normalizedTitle == "window"
        }

        if !window.isVisible,
           !window.isMinimized,
           !window.isHidden,
           !window.hasAXReference,
           !window.canMove,
           !window.canResize {
            let hasVisibleSiblingOnSameDesktop = snapshot.windows.contains { sibling in
                sibling.id != window.id &&
                    sibling.pid == window.pid &&
                    sibling.space == window.space &&
                    sibling.isVisible &&
                    !sibling.isMinimized &&
                    !sibling.isHidden
            }
            if hasVisibleSiblingOnSameDesktop {
                return true
            }
        }

        return false
    }

    func buildOverviewPreviews(from snapshot: LiveStateSnapshot) -> [OverviewDisplayPreview] {
        OverviewPreviewBuilder.build(snapshot: snapshot) { window in
            self.isOverviewExcludedWindow(window, in: snapshot)
        }
    }

    var canControlFocusedWindow: Bool {
        focusedWindowState != nil && doctorSnapshot != nil
    }

    func refreshWindowBadges() {
        guard showWindowBadgeOverlay || showWindowOutlineOverlay else {
            applyWindowBadgeState([], hoveredWindowID: nil)
            return
        }
        guard let snapshot = currentSnapshotForRuntimeConsumers else {
            applyWindowBadgeState([], hoveredWindowID: nil)
            return
        }
        guard snapshot.source == .yabai, !snapshot.degraded else {
            applyWindowBadgeState([], hoveredWindowID: nil)
            return
        }

        let sizeFiltered = snapshot.windows.filter { window in
            guard !window.isMinimized && !window.isHidden else { return false }
            if window.focused { return true }
            return window.frameW > 40 && window.frameH > 24
        }
        guard !sizeFiltered.isEmpty else {
            applyWindowBadgeState([], hoveredWindowID: nil)
            return
        }

        let activeSpaceIndex: Int? =
            sizeFiltered.first(where: \.focused)?.space
            ?? snapshot.spaces.first(where: \.focused)?.index
            ?? snapshot.spaces.first(where: \.visible)?.index
        let activeSpaceCandidates: [WindowState]
        if let activeSpaceIndex {
            activeSpaceCandidates = sizeFiltered.filter { $0.space == activeSpaceIndex }
        } else {
            activeSpaceCandidates = sizeFiltered
        }
        guard !activeSpaceCandidates.isEmpty else {
            applyWindowBadgeState([], hoveredWindowID: nil)
            return
        }

        var selectedWindows = activeSpaceCandidates.filter(\.isVisible)
        let frontmostPID = Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
        let frontmostCandidate = activeSpaceCandidates
            .filter { $0.pid == frontmostPID }
            .sorted { lhs, rhs in
                let lhsArea = lhs.frameW * lhs.frameH
                let rhsArea = rhs.frameW * rhs.frameH
                if lhsArea != rhsArea { return lhsArea > rhsArea }
                return lhs.id < rhs.id
            }
            .first

        if let frontmostCandidate,
           !selectedWindows.contains(where: { $0.id == frontmostCandidate.id }) {
            selectedWindows.append(frontmostCandidate)
        }

        let sortedSelected = selectedWindows.sorted { lhs, rhs in
            if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
            if lhs.app != rhs.app { return lhs.app.localizedCaseInsensitiveCompare(rhs.app) == .orderedAscending }
            return lhs.id < rhs.id
        }

        let explicitFocused = sortedSelected.first(where: \.focused)
        let effectiveFocusedID: Int? = {
            if let frontmostCandidate {
                if explicitFocused == nil { return frontmostCandidate.id }
                if explicitFocused?.pid != frontmostCandidate.pid { return frontmostCandidate.id }
            }
            return explicitFocused?.id
        }()

        let badges = sortedSelected.map { window in
            WindowBadgeState(
                windowID: window.id,
                pid: window.pid,
                app: window.app,
                title: window.title,
                isFloating: window.floating,
                isFocused: window.id == effectiveFocusedID,
                isRuntimeManageable: window.isRuntimeManageable,
                frameX: window.frameX,
                frameY: window.frameY,
                frameW: window.frameW,
                frameH: window.frameH
            )
        }
        applyWindowBadgeState(badges, hoveredWindowID: nil)
    }

    func updateHoveredWindowForBadges(candidates: [WindowState]? = nil) {
        guard let snapshot = currentSnapshotForRuntimeConsumers, snapshot.source == .yabai, !snapshot.degraded else {
            applyWindowBadgeState(windowBadges, hoveredWindowID: nil)
            return
        }
        let windows = candidates ?? snapshot.windows.filter { $0.isVisible && !$0.isMinimized && !$0.isHidden }
        guard !windows.isEmpty else {
            applyWindowBadgeState(windowBadges, hoveredWindowID: nil)
            return
        }

        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens

        let hovered = windows
            .filter { containsMouse(mouse, in: $0, screens: screens) }
            .sorted { lhs, rhs in
                if lhs.focused != rhs.focused { return lhs.focused && !rhs.focused }
                let lhsArea = lhs.frameW * lhs.frameH
                let rhsArea = rhs.frameW * rhs.frameH
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return lhs.id < rhs.id
            }
            .first?
            .id

        applyWindowBadgeState(windowBadges, hoveredWindowID: hovered)
    }

    var shouldShowWindowBehaviorRecommendation: Bool {
        guard let snapshot = doctorSnapshot else { return false }
        let capabilityByKey = Dictionary(uniqueKeysWithValues: snapshot.capabilities.map { ($0.key, $0.status) })
        return capabilityByKey["yabai-binary"] == .available && !yabaiConfigHasManagedSection
    }

    private func containsMouse(_ mouse: NSPoint, in window: WindowState, screens: [NSScreen]) -> Bool {
        let rect = convertTopOriginRectToAppKit(CGRect(x: window.frameX, y: window.frameY, width: window.frameW, height: window.frameH), screens: screens)
        return rect.contains(mouse)
    }

    private func convertTopOriginRectToAppKit(_ rect: CGRect, screens: [NSScreen]) -> CGRect {
        guard !screens.isEmpty else { return rect }
        let referenceMaxY = screens.first(where: { screen in
            abs(screen.frame.minX) < 0.5 && abs(screen.frame.minY) < 0.5
        })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? screens.map(\.frame.maxY).min()
            ?? rect.maxY
        return CGRect(
            x: rect.origin.x,
            y: referenceMaxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func applyWindowBadgeState(_ badges: [WindowBadgeState], hoveredWindowID: Int?) {
        if windowBadges != badges {
            windowBadges = badges
        }
        if hoveredWindowIDForBadges != hoveredWindowID {
            hoveredWindowIDForBadges = hoveredWindowID
        }
    }
}
