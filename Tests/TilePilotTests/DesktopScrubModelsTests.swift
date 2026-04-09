#if canImport(XCTest)
import AppKit
import XCTest
@testable import TilePilot

final class DesktopScrubModelsTests: XCTestCase {
    func testLoadFromUserDefaultsFallsBackToDefaultSelectionWhenTooFewKeysProvided() {
        let loaded = DesktopScrubModifier.loadFromUserDefaults(rawValues: ["option"])

        XCTAssertEqual(loaded, DesktopScrubModifier.defaultSelection)
    }

    func testNormalizePreservesCanonicalModifierOrder() {
        let normalized = DesktopScrubModifier.normalize([.command, .shift, .option])

        XCTAssertEqual(normalized, [.shift, .option, .command])
    }

    func testFlagsRoundTripBackToModifiers() {
        let modifiers: [DesktopScrubModifier] = [.shift, .control, .option]
        let flags = DesktopScrubModifier.flags(for: modifiers)

        XCTAssertEqual(DesktopScrubModifier.from(flags: flags), modifiers)
    }
}
#endif
