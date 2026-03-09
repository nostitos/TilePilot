#if canImport(XCTest)
import XCTest
@testable import TilePilot

final class PerformanceModelsTests: XCTestCase {
    func testPresetDefaultsMatchExpectedValues() {
        XCTAssertEqual(PerformanceSettings.balanced.foregroundPollingSeconds, 1.5)
        XCTAssertEqual(PerformanceSettings.balanced.keepOnTopEnforcementSeconds, 2.5)
        XCTAssertEqual(PerformanceSettings.responsive.backgroundPollingSeconds, 2.0)
        XCTAssertEqual(PerformanceSettings.passiveBaseline.backgroundPollingSeconds, 10.0)
        XCTAssertEqual(PerformanceSettings.lowCPU.keepOnTopEnforcementEnabled, false)
    }

    func testMatchesPresetDetectsBalancedAndCustom() {
        XCTAssertTrue(PerformanceSettings.balanced.matchesPreset(.balanced))
        XCTAssertEqual(PerformanceSettings.passiveBaseline.overlayRefreshPolicy, .reduced)

        var custom = PerformanceSettings.balanced
        custom.miniMapHoverTitlesEnabled = false

        XCTAssertFalse(custom.matchesPreset(.balanced))
    }
}
#endif
