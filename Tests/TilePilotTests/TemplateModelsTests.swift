#if canImport(XCTest)
import CoreGraphics
import XCTest
@testable import TilePilot

final class TemplateModelsTests: XCTestCase {
    func testDisplayShapeKeyMatchesEquivalentAspectRatios() {
        let key = DisplayShapeKey.from(width: 3840, height: 2160)

        XCTAssertNotNil(key)
        XCTAssertTrue(key?.matches(width: 2560, height: 1440) == true)
        XCTAssertFalse(key?.matches(width: 1512, height: 982) == true)
    }

    func testWindowLayoutTemplateSortsTopToBottomThenLeftToRight() {
        let lowerLeft = WindowLayoutSlot(normalizedX: 0.05, normalizedY: 0.55, normalizedWidth: 0.3, normalizedHeight: 0.3)
        let topRight = WindowLayoutSlot(normalizedX: 0.55, normalizedY: 0.08, normalizedWidth: 0.3, normalizedHeight: 0.3)
        let topLeft = WindowLayoutSlot(normalizedX: 0.05, normalizedY: 0.08, normalizedWidth: 0.3, normalizedHeight: 0.3)

        let ordered = WindowLayoutTemplate.sortedSlots([lowerLeft, topRight, topLeft])

        XCTAssertEqual(ordered.map(\.id), [topLeft.id, topRight.id, lowerLeft.id])
    }

    func testWindowLayoutSlotDecodesMissingAllowedAppsAsAnyApp() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000111",
          "normalizedX": 0.1,
          "normalizedY": 0.2,
          "normalizedWidth": 0.3,
          "normalizedHeight": 0.4,
          "zIndex": 2
        }
        """

        let slot = try JSONDecoder().decode(WindowLayoutSlot.self, from: Data(json.utf8))

        XCTAssertEqual(slot.allowedApps, [])
        XCTAssertEqual(slot.zIndex, 2)
    }

    func testWindowLayoutSlotCanonicalizesAllowedApps() {
        let slot = WindowLayoutSlot(
            normalizedX: 0.1,
            normalizedY: 0.1,
            normalizedWidth: 0.4,
            normalizedHeight: 0.4,
            allowedApps: [" Telegram ", "telegram", "Slack"]
        )

        XCTAssertEqual(slot.allowedApps, ["Slack", "Telegram"])
    }

    func testClampedNormalizedTemplateRectStaysWithinCanvasBounds() {
        let rect = clampedNormalizedTemplateRect(CGRect(x: 0.92, y: 0.95, width: 0.2, height: 0.2))

        XCTAssertGreaterThanOrEqual(rect.minX, 0)
        XCTAssertGreaterThanOrEqual(rect.minY, 0)
        XCTAssertLessThanOrEqual(rect.maxX, 1)
        XCTAssertLessThanOrEqual(rect.maxY, 1)
        XCTAssertGreaterThanOrEqual(rect.width, 0.04)
        XCTAssertGreaterThanOrEqual(rect.height, 0.04)
    }

    func testSplitTemplateSlotRectVerticalProducesTwoHalves() {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let split = splitTemplateSlotRect(rect, axis: .vertical)

        XCTAssertNotNil(split)
        XCTAssertEqual(split?.0, CGRect(x: 0, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(split?.1, CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
    }

    func testSplitTemplateSlotRectHorizontalProducesTwoHalves() {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let split = splitTemplateSlotRect(rect, axis: .horizontal)

        XCTAssertNotNil(split)
        XCTAssertEqual(split?.0, CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(split?.1, CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
    }
}
#endif
