#if canImport(XCTest)
import XCTest
@testable import SlayNodeMenuBar

final class WindowDashboardSupportTests: XCTestCase {
    func testMakeWorkspaceSectionsGroupsServicesByWorkingDirectory() {
        let descriptor = ServerDescriptor(
            name: "Vite",
            displayName: "Vite",
            category: .bundler,
            runtime: "Node.js",
            packageManager: "npm",
            script: "dev",
            details: "Vite dev server",
            portHints: []
        )

        let processes = [
            makeProcess(
                pid: 4301,
                title: "frontend",
                categoryBadge: "Bundler",
                actualPorts: [4317],
                projectName: "slaynode-workspace-fixture",
                workingDirectory: "/tmp/slaynode-workspace-fixture",
                descriptor: descriptor
            ),
            makeProcess(
                pid: 4302,
                title: "backend",
                subtitle: "tsx watch",
                categoryBadge: "API/Backend",
                actualPorts: [4318],
                projectName: "slaynode-workspace-fixture",
                workingDirectory: "/tmp/slaynode-workspace-fixture",
                descriptor: descriptor
            )
        ]

        let sections = makeWorkspaceSections(from: processes)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].title, "slaynode-workspace-fixture")
        XCTAssertEqual(sections[0].serviceCount, 2)
        XCTAssertEqual(sections[0].actualPortCount, 2)
        XCTAssertEqual(sections[0].roleSummary, "Bundler + API/Backend")
        XCTAssertEqual(sections[0].dominantCategory, "Bundler")
    }

    func testMakeWorkspaceSectionsKeepsStandaloneProcessesSeparate() {
        let processes = [
            makeProcess(pid: 5001, title: "vite", categoryBadge: "Bundler"),
            makeProcess(pid: 5002, title: "tsx", categoryBadge: "TypeScript Runner")
        ]

        let sections = makeWorkspaceSections(from: processes)

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.map(\.title), ["vite", "tsx"])
        XCTAssertEqual(sections.map(\.serviceCount), [1, 1])
    }

    func testDetectionConfidenceReturnsHighForWellResolvedRuntime() {
        let process = makeProcess(
            pid: 6001,
            actualPorts: [3000],
            projectName: "frontend",
            workingDirectory: "/Users/test/frontend",
            descriptor: ServerDescriptor(
                name: "Next.js",
                displayName: "Next.js",
                category: .webFramework,
                runtime: "Node.js",
                packageManager: "npm",
                script: "dev",
                details: "App Router dev server",
                portHints: []
            )
        )

        let confidence = detectionConfidence(for: process)

        XCTAssertEqual(confidence.kind, .high)
        XCTAssertEqual(confidence.label, "High confidence")
    }

    func testDetectionSignalsExposeLivePortWorkspaceAndWrapperContext() {
        let process = makeProcess(
            pid: 6002,
            actualPorts: [4317],
            projectName: "fixture",
            workingDirectory: "/tmp/fixture",
            descriptor: ServerDescriptor(
                name: "Vite",
                displayName: "Vite",
                category: .bundler,
                runtime: "Node.js",
                packageManager: "npm",
                script: "dev",
                details: "Vite dev server",
                portHints: []
            )
        )

        let signals = detectionSignals(for: process)

        XCTAssertEqual(signals.map(\.title), [
            "Live port evidence",
            "Workspace resolved",
            "Known runtime signature",
            "Wrapper command"
        ])
    }

    func testSlayScopeNarrativeExplainsWrapperShutdown() {
        let process = makeProcess(
            pid: 6003,
            descriptor: ServerDescriptor(
                name: "TSX",
                displayName: "TSX",
                category: .utility,
                runtime: "Node.js",
                packageManager: "pnpm",
                script: "api",
                details: nil,
                portHints: []
            )
        )

        let narrative = slayScopeNarrative(for: process)

        XCTAssertTrue(narrative.contains("package-manager wrapper"))
        XCTAssertTrue(narrative.contains("child runtime"))
    }

    private func makeProcess(
        pid: Int32,
        title: String = "fixture",
        subtitle: String = "npm dev",
        categoryBadge: String? = "Bundler",
        actualPorts: [Int] = [],
        likelyPorts: [Int] = [],
        projectName: String? = nil,
        workingDirectory: String? = nil,
        descriptor: ServerDescriptor = .unknown,
        command: String = "npm run dev"
    ) -> NodeProcessItemViewModel {
        NodeProcessItemViewModel(
            id: pid,
            pid: pid,
            title: title,
            subtitle: subtitle,
            categoryBadge: categoryBadge,
            portBadges: actualPorts.map { .init(text: ":\($0)", isLikely: false) }
                + likelyPorts.map { .init(text: ":\($0)", isLikely: true) },
            infoChips: [],
            projectName: projectName,
            uptimeDescription: "1m",
            startTimeDescription: "1 minute ago",
            command: command,
            workingDirectory: workingDirectory,
            descriptor: descriptor,
            searchIndex: [
                title,
                subtitle,
                categoryBadge,
                projectName,
                workingDirectory,
                command
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased(),
            isStopping: false
        )
    }
}
#endif
