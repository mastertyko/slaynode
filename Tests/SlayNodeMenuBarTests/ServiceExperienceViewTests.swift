#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class ServiceExperienceViewTests: XCTestCase {
    func testServiceListEmptyStateShowsDiscoveryErrorVariant() {
        let content = serviceListEmptyStateContent(
            searchText: "",
            lastError: "ps failed"
        )

        XCTAssertEqual(content.title, "Discovery Needs Attention")
        XCTAssertEqual(content.systemImage, "exclamationmark.triangle")
    }

    func testServiceListEmptyStateShowsSearchVariant() {
        let content = serviceListEmptyStateContent(
            searchText: "vite",
            lastError: nil
        )

        XCTAssertEqual(content.title, "No Matching Services")
        XCTAssertEqual(content.systemImage, "magnifyingglass")
    }

    func testServiceListEmptyStateShowsDiscoveryVariantWithoutSearchOrError() {
        let content = serviceListEmptyStateContent(
            searchText: "  ",
            lastError: " \n "
        )

        XCTAssertEqual(content.title, "No Services Found")
        XCTAssertEqual(content.systemImage, "bolt.slash")
    }
}
#endif
