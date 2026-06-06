#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class RuntimePresentationSupportTests: XCTestCase {
    func testRuntimePortBadgeAccessibilityLabelForLivePort() {
        let badge = NodeProcessItemViewModel.PortBadge(text: "3000", isLikely: false)

        XCTAssertEqual(runtimePortBadgeAccessibilityLabel(for: badge), "Live port 3000")
    }

    func testRuntimePortBadgeAccessibilityLabelForLikelyPort() {
        let badge = NodeProcessItemViewModel.PortBadge(text: "4173", isLikely: true)

        XCTAssertEqual(runtimePortBadgeAccessibilityLabel(for: badge), "Likely port 4173")
    }

    func testRuntimeStatusPillAccessibilityLabelReturnsText() {
        XCTAssertEqual(
            runtimeStatusPillAccessibilityLabel(text: "High confidence"),
            "High confidence"
        )
    }
}
#endif
