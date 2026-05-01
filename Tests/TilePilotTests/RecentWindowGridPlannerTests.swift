#if canImport(XCTest)
import XCTest
@testable import TilePilot

final class RecentWindowGridPlannerTests: XCTestCase {
    func testOptimizedGridChoicesForCommonWindowCounts() {
        let expected: [Int: (rows: Int, cols: Int, spare: Int)] = [
            2: (1, 2, 0),
            3: (1, 3, 0),
            4: (2, 2, 0),
            5: (2, 3, 1),
            6: (2, 3, 0),
            7: (2, 4, 1),
            8: (2, 4, 0),
            9: (3, 3, 0),
            10: (2, 5, 0),
            11: (3, 4, 1),
            12: (3, 4, 0),
            13: (3, 5, 2),
        ]

        for count in 2...13 {
            let grid = RecentWindowGridPlanner.dimensions(windowCount: count, displayAspectRatio: 1.6)
            let spare = (grid.rows * grid.cols) - count

            XCTAssertEqual(grid.rows, expected[count]?.rows, "rows for \(count) windows")
            XCTAssertEqual(grid.cols, expected[count]?.cols, "cols for \(count) windows")
            XCTAssertEqual(spare, expected[count]?.spare, "spare cells for \(count) windows")
        }
    }

    func testSpareBottomCellsAreFilledByVerticalSpans() {
        assertSpannedPlacements(windowCount: 5, expectedSpannedIndexes: [2])
        assertSpannedPlacements(windowCount: 7, expectedSpannedIndexes: [3])
        assertSpannedPlacements(windowCount: 11, expectedSpannedIndexes: [7])
        assertSpannedPlacements(windowCount: 13, expectedSpannedIndexes: [8, 9])
    }

    func testPerfectGridsDoNotSpanWindows() {
        for count in [6, 8, 9, 10, 12] {
            let grid = RecentWindowGridPlanner.dimensions(windowCount: count, displayAspectRatio: 1.6)
            let placements = RecentWindowGridPlanner.placements(windowCount: count, rows: grid.rows, cols: grid.cols)

            XCTAssertEqual(placements.map(\.rowSpan), Array(repeating: 1, count: count), "row spans for \(count) windows")
        }
    }

    private func assertSpannedPlacements(windowCount count: Int, expectedSpannedIndexes: Set<Int>) {
        let grid = RecentWindowGridPlanner.dimensions(windowCount: count, displayAspectRatio: 1.6)
        let placements = RecentWindowGridPlanner.placements(windowCount: count, rows: grid.rows, cols: grid.cols)

        for index in placements.indices {
            let expectedSpan = expectedSpannedIndexes.contains(index) ? 2 : 1
            XCTAssertEqual(placements[index].rowSpan, expectedSpan, "row span for index \(index) with \(count) windows")
        }
    }
}
#endif
