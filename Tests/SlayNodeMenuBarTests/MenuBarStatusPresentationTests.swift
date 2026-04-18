#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class MenuBarStatusPresentationTests: XCTestCase {
    func testCriticalServicesTakePriorityOverRefreshing() {
        let presentation = MenuBarStatusPresentation.make(
            activeCount: 4,
            unhealthyCount: 2,
            isRefreshing: true,
            hasError: false
        )

        XCTAssertEqual(presentation.symbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(presentation.countText, "2")
        XCTAssertEqual(presentation.statusText, "2 services need attention")
    }

    func testErrorStateAppearsWithoutCriticalServices() {
        let presentation = MenuBarStatusPresentation.make(
            activeCount: 3,
            unhealthyCount: 0,
            isRefreshing: false,
            hasError: true
        )

        XCTAssertEqual(presentation.symbolName, "exclamationmark.circle.fill")
        XCTAssertNil(presentation.countText)
        XCTAssertEqual(presentation.statusText, "Last action needs attention")
    }

    func testRefreshingStateAppearsWhenHealthy() {
        let presentation = MenuBarStatusPresentation.make(
            activeCount: 2,
            unhealthyCount: 0,
            isRefreshing: true,
            hasError: false
        )

        XCTAssertEqual(presentation.symbolName, "arrow.trianglehead.2.clockwise.rotate.90.circle.fill")
        XCTAssertNil(presentation.countText)
    }

    func testActiveStateShowsCompactCount() {
        let presentation = MenuBarStatusPresentation.make(
            activeCount: 12,
            unhealthyCount: 0,
            isRefreshing: false,
            hasError: false
        )

        XCTAssertEqual(presentation.symbolName, "shippingbox.circle.fill")
        XCTAssertEqual(presentation.countText, "9+")
        XCTAssertEqual(presentation.statusText, "12 active services")
    }

    func testIdleStateHasNoCount() {
        let presentation = MenuBarStatusPresentation.make(
            activeCount: 0,
            unhealthyCount: 0,
            isRefreshing: false,
            hasError: false
        )

        XCTAssertEqual(presentation.symbolName, "shippingbox.circle")
        XCTAssertNil(presentation.countText)
        XCTAssertEqual(presentation.statusText, "No active services")
    }
}
#endif
