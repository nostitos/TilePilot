import Foundation

enum RecentWindowTilerMode: String, CaseIterable, Identifiable, Sendable {
    case autoTiled
    case floatingGrid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .autoTiled:
            return "Auto-Tiled"
        case .floatingGrid:
            return "Floating Grid"
        }
    }
}

struct RecentWindowTilerCandidate: Identifiable, Equatable, Sendable {
    let windowID: Int
    let pid: Int
    let app: String
    let title: String
    let focused: Bool
    let floating: Bool
    let canAutoTile: Bool
    let canFloatingGrid: Bool

    var id: Int { windowID }

    var isAXOnly: Bool {
        !canAutoTile && canFloatingGrid
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasDistinctTitle: Bool {
        guard !trimmedTitle.isEmpty else { return false }
        return Self.normalizedLabel(trimmedTitle) != Self.normalizedLabel(app)
    }

    var primaryDisplayText: String {
        hasDistinctTitle ? trimmedTitle : app
    }

    var secondaryDisplayText: String? {
        hasDistinctTitle ? app : nil
    }

    func isSelectable(in mode: RecentWindowTilerMode) -> Bool {
        switch mode {
        case .autoTiled:
            return canAutoTile
        case .floatingGrid:
            return canFloatingGrid
        }
    }

    func disabledReason(in mode: RecentWindowTilerMode) -> String? {
        guard !isSelectable(in: mode) else { return nil }
        switch mode {
        case .autoTiled:
            return "\(app) cannot join yabai Auto-Tiled mode right now. Use Floating Grid for AX-only placement."
        case .floatingGrid:
            return "\(app) cannot be moved or resized right now."
        }
    }

    private static func normalizedLabel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct RecentWindowTilerPresentationState: Equatable, Sendable {
    var candidates: [RecentWindowTilerCandidate]
    var selectedWindowIDs: Set<Int>
    var mode: RecentWindowTilerMode
    let displayAspectRatio: Double

    var effectiveSelectedWindowIDs: Set<Int> {
        selectedWindowIDs.intersection(selectableWindowIDs(for: mode))
    }

    var orderedEffectiveSelectedWindowIDs: [Int] {
        candidates
            .filter { effectiveSelectedWindowIDs.contains($0.windowID) }
            .map(\.windowID)
    }

    var orderedEffectiveSelectedCandidates: [RecentWindowTilerCandidate] {
        candidates.filter { effectiveSelectedWindowIDs.contains($0.windowID) }
    }

    var selectedCount: Int {
        effectiveSelectedWindowIDs.count
    }

    func selectableWindowIDs(for mode: RecentWindowTilerMode) -> Set<Int> {
        Set(candidates.filter { $0.isSelectable(in: mode) }.map(\.windowID))
    }
}

struct RecentWindowGridPlanner {
    static func dimensions(windowCount count: Int, displayAspectRatio: Double) -> (rows: Int, cols: Int) {
        guard count > 1 else { return (1, 1) }

        let aspectRatio = max(displayAspectRatio, 0.5)
        let landscape = aspectRatio >= 1
        var best: GridCandidate?

        for rows in 1...count {
            let cols = Int(ceil(Double(count) / Double(rows)))
            guard rows * cols >= count else { continue }
            if landscape, cols < rows { continue }
            if !landscape, rows < cols { continue }

            let spare = (rows * cols) - count
            let gridAspect = Double(cols) / Double(rows)
            let aspectPenalty = abs(log(gridAspect / aspectRatio))
            let sparePenalty = (Double(spare) / Double(count)) * 2.2
            let stripPenalty = count > 3 && min(rows, cols) == 1 ? 1.0 : 0
            let score = aspectPenalty + sparePenalty + stripPenalty
            let candidate = GridCandidate(rows: rows, cols: cols, spare: spare, score: score)

            if best.map({ candidate.isBetter(than: $0) }) ?? true {
                best = candidate
            }
        }

        guard let best else {
            let cols = max(1, Int(ceil(sqrt(Double(count) * aspectRatio))))
            return (max(1, Int(ceil(Double(count) / Double(cols)))), cols)
        }

        return (best.rows, best.cols)
    }

    static func placements(windowCount count: Int, rows: Int, cols: Int) -> [RecentWindowGridPlacement] {
        guard count > 0 else { return [] }

        var placements = (0..<count).map { index in
            RecentWindowGridPlacement(
                row: index / max(cols, 1),
                col: index % max(cols, 1),
                rowSpan: 1,
                colSpan: 1
            )
        }

        let lastRowCount = count % max(cols, 1)
        guard rows > 1, lastRowCount > 0 else { return placements }

        for col in lastRowCount..<cols {
            let indexAboveSpareCell = ((rows - 2) * cols) + col
            guard placements.indices.contains(indexAboveSpareCell) else { continue }
            placements[indexAboveSpareCell].rowSpan = 2
        }

        return placements
    }

    private struct GridCandidate {
        let rows: Int
        let cols: Int
        let spare: Int
        let score: Double

        func isBetter(than other: GridCandidate) -> Bool {
            if abs(score - other.score) > 0.0001 {
                return score < other.score
            }
            if spare != other.spare {
                return spare < other.spare
            }
            return abs(rows - cols) < abs(other.rows - other.cols)
        }
    }
}

struct RecentWindowGridPlacement: Equatable, Sendable {
    let row: Int
    let col: Int
    var rowSpan: Int
    let colSpan: Int
}
