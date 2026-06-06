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

    func testRuntimeActionAccessibilityLabelForOpenPort() {
        XCTAssertEqual(
            runtimeActionAccessibilityLabel(.openPort(3000), processTitle: "demo-api"),
            "Open localhost port 3000 for demo-api"
        )
    }

    func testRuntimeActionAccessibilityLabelForCopyCommand() {
        XCTAssertEqual(
            runtimeActionAccessibilityLabel(.copyCommand, processTitle: "demo-api"),
            "Copy redacted command for demo-api"
        )
    }

    func testRuntimeActionAccessibilityLabelForSlay() {
        XCTAssertEqual(
            runtimeActionAccessibilityLabel(.slay, processTitle: "demo-api"),
            "Slay demo-api"
        )
    }
}
#endif
