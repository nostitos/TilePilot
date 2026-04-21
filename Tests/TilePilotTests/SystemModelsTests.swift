#if canImport(XCTest)
import XCTest
@testable import TilePilot

final class SystemModelsTests: XCTestCase {
    func testMissionControlChecklistItemsProvideDefaultsWhenChecksMissing() {
        let items = buildMissionControlChecklistItems(from: [])

        XCTAssertEqual(items.map(\.id), ["mru-spaces", "spans-displays"])
        XCTAssertEqual(items.map(\.expectedValue), ["Off", "On"])
        XCTAssertEqual(items.map(\.status), [.unknown, .unknown])
        XCTAssertNil(items[0].actualValue)
        XCTAssertNil(items[1].actualValue)
    }

    func testMissionControlChecklistItemsTranslateRawValuesToUIValues() {
        let items = buildMissionControlChecklistItems(from: [
            MissionControlCheck(
                key: "mru-spaces",
                expected: "0",
                actual: "1",
                status: .warning,
                message: "MRU spaces enabled"
            ),
            MissionControlCheck(
                key: "spans-displays",
                expected: "0",
                actual: "0",
                status: .pass,
                message: "Separate spaces enabled"
            ),
        ])

        XCTAssertEqual(items[0].title, "Automatically rearrange Spaces based on most recent use")
        XCTAssertEqual(items[0].expectedValue, "Off")
        XCTAssertEqual(items[0].actualValue, "On")
        XCTAssertEqual(items[1].title, "Displays have separate Spaces")
        XCTAssertEqual(items[1].expectedValue, "On")
        XCTAssertEqual(items[1].actualValue, "On")
    }
}
#endif
