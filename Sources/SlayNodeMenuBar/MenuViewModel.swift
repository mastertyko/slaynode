import Combine
import Foundation

struct NodeProcessItemViewModel: Identifiable, Equatable {
    struct PortBadge: Hashable {
        let text: String
        let isLikely: Bool
    }

    struct InfoChip: Hashable {
        let text: String
        let systemImage: String?
    }

    let id: Int32
    let pid: Int32
    let title: String
    let subtitle: String
    let categoryBadge: String?
    let portBadges: [PortBadge]
    let infoChips: [InfoChip]
    let projectName: String?
    let uptimeDescription: String
    let startTimeDescription: String
    let command: String
    let workingDirectory: String?
    let descriptor: ServerDescriptor
    let isStopping: Bool
}

@MainActor
final class MenuViewModel: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var processes: [NodeProcessItemViewModel] = []
    @Published var lastError: String?
    @Published var lastUpdated: Date?

    let preferences: PreferencesStore

    private let monitor: ProcessMonitor
    private let killer = ProcessKiller()
    private var cancellables: Set<AnyCancellable> = []
    private var stoppingPids: Set<Int32> = []
    private var latestProcesses: [NodeProcess] = []
    
    private func writeToLogFile(_ message: String) {
        // Use simple console logging to avoid threading issues
        print("SlayNode: \(message)")
    }

    init(preferences: PreferencesStore = PreferencesStore(), monitor: ProcessMonitor = ProcessMonitor()) {
        self.preferences = preferences
        self.monitor = monitor

        // Start with loading state and trigger real process detection immediately
        isLoading = true
        processes = []
        lastError = nil
        lastUpdated = Date()

        print("🚀 MenuViewModel initialized - starting real process detection")

        // Trigger immediate refresh to show real data
        refresh()

        // Add silent automatic refresh every 5 seconds
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        print("🔄 DYNAMIC PROCESS DETECTION")
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var realProcesses: [NodeProcessItemViewModel] = []

            // Method 1: Use simple ps + grep combination
            let task = Process()
            task.launchPath = "/bin/bash"
            task.arguments = ["-c", "ps -axo pid=,command= | grep -E '^[ ]*[0-9]+ (node |npm |yarn |pnpm |npx )' | head -15"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                print("📋 Found \(output.split(whereSeparator: \.isNewline).count) potential processes")

                let lines = output.split(whereSeparator: \.isNewline)

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                    guard parts.count >= 2,
                          let pid = Int32(parts[0]),
                          pid > 0 else { continue }

                    let command = String(parts[1])

                    // Create a simple process VM - we know the UI logic works
                    let title = self.extractSimpleTitle(from: command)
                    let ports = self.extractSimplePorts(from: command)
                    let mainPort = ports.first ?? 0 // 0 means no port detected

                    // Create port badges and info chips only if port is detected
                    let portBadges: [NodeProcessItemViewModel.PortBadge] = mainPort > 0 ? [.init(text: ":\(mainPort)", isLikely: false)] : []

                    var infoChips: [NodeProcessItemViewModel.InfoChip] = [
                        .init(text: "Node.js", systemImage: "cpu")
                    ]

                    if mainPort > 0 {
                        infoChips.append(.init(text: "http://localhost:\(mainPort)", systemImage: "link"))
                    }

                    // Extract a meaningful category based on the command
                    let category = self.extractSimpleCategory(from: command)

                    let processVM = NodeProcessItemViewModel(
                        id: pid,
                        pid: pid,
                        title: title,
                        subtitle: command.count > 50 ? String(command.prefix(50)) + "..." : command,
                        categoryBadge: category,
                        portBadges: portBadges,
                        infoChips: infoChips,
                        projectName: self.extractSimpleProjectName(from: command),
                        uptimeDescription: "Running",
                        startTimeDescription: "Active",
                        command: command,
                        workingDirectory: nil,
                        descriptor: .init(
                            name: title,
                            displayName: title,
                            category: .webFramework,
                            runtime: "Node.js",
                            packageManager: nil,
                            script: "server",
                            details: "PID: \(pid)",
                            portHints: mainPort > 0 ? [mainPort] : []
                        ),
                        isStopping: false
                    )
                    realProcesses.append(processVM)
                    print("✅ Dynamic process: \(title) (PID: \(pid))")
                }

                print("🎯 DYNAMIC COUNT: \(realProcesses.count) processes")

            } catch {
                print("❌ Process detection failed: \(error)")
            }

            DispatchQueue.main.async {
                self.isLoading = false
                self.lastUpdated = Date()

                // Always show the dynamically found processes
                self.processes = realProcesses
                if realProcesses.isEmpty {
                    print("📝 No Node.js processes found")
                } else {
                    print("🎉 Showing \(realProcesses.count) Node.js processes!")
                }
            }
        }
    }

    // Simple title extraction for dynamic detection
    private func extractSimpleTitle(from command: String) -> String {
        let lowercase = command.lowercased()

        if lowercase.contains("next") && lowercase.contains("dev") {
            return "Next.js Dev Server"
        } else if lowercase.contains("vite") && (lowercase.contains("dev") || lowercase.contains("serve")) {
            return "Vite Dev Server"
        } else if lowercase.contains("npm exec") {
            return "NPM Package"
        } else if lowercase.hasPrefix("npm ") {
            return "NPM Process"
        } else if lowercase.hasPrefix("node ") && lowercase.contains("server") {
            return "Node.js Server"
        } else if lowercase.hasPrefix("node ") {
            return "Node.js Process"
        } else {
            return "Development Process"
        }
    }

    // Simple port extraction - improved with multiple patterns
    private func extractSimplePorts(from command: String) -> [Int] {
        var ports: Set<Int> = []

        // Pattern 1: Traditional :3000 syntax
        let patterns = [
            #":(\d{3,5})"#,           // :3000, :8080, etc.
            #"--port[ =](\d{3,5})"#,  // --port 3000, --port=3000
            #"-p[ =](\d{3,5})"#,      // -p 3000, -p=3000
            #"listen\((\d{3,5})"#,    // listen(3000)
            #"PORT[ =](\d{3,5})"#,    // PORT=3000, PORT 3000
            #"port[ =](\d{3,5})"#     // port=3000, port 3000
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }

            let matches = regex.matches(in: command, range: NSRange(command.startIndex..., in: command))
            for match in matches {
                if let range = Range(match.range(at: 1), in: command),
                   let port = Int(command[range]) {
                    // Validate port range (1-65535, but we focus on common dev ports)
                    if port >= 1 && port <= 65535 {
                        ports.insert(port)
                    }
                }
            }
        }

        // If no ports found and it's a common framework, try to infer default ports
        if ports.isEmpty {
            let lowercase = command.lowercased()
            if lowercase.contains("next") && lowercase.contains("dev") {
                ports.insert(3000) // Next.js default
            } else if lowercase.contains("vite") && (lowercase.contains("dev") || lowercase.contains("serve")) {
                ports.insert(5173) // Vite default
            } else if lowercase.contains("react-scripts") {
                ports.insert(3000) // Create React App default
            } else if lowercase.contains("nuxt") && lowercase.contains("dev") {
                ports.insert(3000) // Nuxt.js default
            }
        }

        return Array(ports).sorted()
    }

    // Simple project name extraction
    private func extractSimpleProjectName(from command: String) -> String? {
        if let slashRange = command.range(of: "/", options: .backwards) {
            let afterSlash = String(command[slashRange.upperBound...])
            let components = afterSlash.split(separator: " ").prefix(2)
            if let firstComponent = components.first {
                return String(firstComponent)
            }
        }
        return nil
    }

    // Simple category extraction for dynamic detection
    private func extractSimpleCategory(from command: String) -> String? {
        let lowercase = command.lowercased()

        // Web Frameworks
        if lowercase.contains("next") || lowercase.contains("nuxt") {
            return "Web Framework"

        // Bundlers and Build Tools
        } else if lowercase.contains("vite") || lowercase.contains("webpack") || lowercase.contains("parcel") || lowercase.contains("rollup") {
            return "Bundler"

        // Frameworks
        } else if lowercase.contains("react-scripts") || lowercase.contains("angular") || lowercase.contains("vue") {
            return "Framework"

        // Development Utilities
        } else if lowercase.contains("nodemon") || lowercase.contains("pm2") || lowercase.contains("ts-node") {
            return "Utility"

        // Servers
        } else if lowercase.contains("http-server") || lowercase.contains("live-server") ||
                  lowercase.contains("listen(") || lowercase.contains("express") ||
                  lowercase.contains("koa") || lowercase.contains("fastify") {
            return "Server"

        // Development Tools
        } else if lowercase.contains("browser-sync") || lowercase.contains("eslint") ||
                  lowercase.contains("prettier") || lowercase.contains("jest") {
            return "Tool"

        // MCP (Model Context Protocol) Tools - based on your actual processes
        } else if lowercase.contains("chrome-devtools") || lowercase.contains("context7") ||
                  lowercase.contains("zai-mcp") || lowercase.contains("mcp") {
            return "MCP Tool"

        // Package Manager Scripts
        } else if lowercase.hasPrefix("npm run") || lowercase.hasPrefix("yarn") ||
                  lowercase.hasPrefix("pnpm") || lowercase.contains("npm exec") {
            return "Development"

        // Generic Node.js servers
        } else if lowercase.hasPrefix("node ") && (lowercase.contains("server") ||
                                                     lowercase.contains("app") ||
                                                     lowercase.contains("api")) {
            return "Server"

        // Generic Node.js processes
        } else if lowercase.hasPrefix("node ") {
            return "Node.js"
        }

        return nil // No category badge if we can't identify it meaningfully
    }

    private func safeParseProcessesFromBackground(_ output: String) async -> [NodeProcessItemViewModel] {
        let lines = output.split(whereSeparator: \.isNewline)
        var nodeProcesses: [NodeProcessItemViewModel] = []

        // Limit to prevent memory issues
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Safe parsing with guards
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  pid > 0 else { continue }

            let command = String(parts[1])
            guard !command.isEmpty else { continue }

            // Check if it's a Node.js related process
            if isNodeProcess(command) {
                if let processVM = createRealProcessViewModel(pid: pid, command: command) {
                    nodeProcesses.append(processVM)
                }
            }
        }

        return Array(nodeProcesses.prefix(5)) // Limit to 5 processes for safety
    }

    private func performSafeProcessDetection() async {
        let pipe = Pipe()
        let process = Process()
        process.launchPath = "/bin/ps"
        process.arguments = ["-axo", "pid=,command="]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                let realProcesses = safeParseProcesses(output)
                print("✅ Found \(realProcesses.count) real Node.js processes")

                await MainActor.run {
                    // Always show the dynamically found processes
                    self.processes = realProcesses
                    if realProcesses.isEmpty {
                        print("📝 No Node.js processes found")
                    } else {
                        print("🎉 Showing \(realProcesses.count) real processes!")
                    }
                }
            }
        } catch {
            print("⚠️ Process detection failed: \(error)")
            await MainActor.run {
                self.processes = []
                self.lastError = "Failed to detect processes: \(error.localizedDescription)"
            }
        }
    }

    private func safeParseProcesses(_ output: String) -> [NodeProcessItemViewModel] {
        let lines = output.split(whereSeparator: \.isNewline)
        var nodeProcesses: [NodeProcessItemViewModel] = []

        // Limit to prevent memory issues
        for line in lines.prefix(10) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Safe parsing with guards
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]),
                  pid > 0 else { continue }

            let command = String(parts[1])
            guard !command.isEmpty else { continue }

            // Check if it's a Node.js related process
            if isNodeProcess(command) {
                if let processVM = createRealProcessViewModel(pid: pid, command: command) {
                    nodeProcesses.append(processVM)
                }
            }
        }

        return Array(nodeProcesses.prefix(5)) // Limit to 5 processes for safety
    }

    private func createRealProcessViewModel(pid: Int32, command: String) -> NodeProcessItemViewModel? {
        // Extract information safely
        let title = extractRealTitle(from: command)
        let subtitle = extractRealSubtitle(from: command)
        let ports = extractRealPorts(from: command)
        let category = extractRealCategory(from: command)
        let projectName = extractRealProjectName(from: command)

        // Create enhanced info chips with more details
        var infoChips: [NodeProcessItemViewModel.InfoChip] = [
            .init(text: "Node.js", systemImage: "cpu")
        ]

        // Add port-based URL if available
        if let mainPort = ports.first {
            infoChips.append(.init(text: "http://localhost:\(mainPort)", systemImage: "link"))
        }

        // Add process type indicator
        if category != nil {
            infoChips.append(.init(text: "Server", systemImage: "server.rack"))
        }

        return NodeProcessItemViewModel(
            id: pid,
            pid: pid,
            title: title,
            subtitle: subtitle,
            categoryBadge: category,
            portBadges: ports.map { .init(text: ":\($0)", isLikely: false) },
            infoChips: infoChips,
            projectName: projectName,
            uptimeDescription: "Running",
            startTimeDescription: "Active",
            command: command,
            workingDirectory: nil,
            descriptor: .init(
                name: title,
                displayName: title,
                category: .webFramework,
                runtime: "Node.js",
                packageManager: nil,
                script: subtitle,
                details: "Process ID: \(pid)",
                portHints: ports
            ),
            isStopping: false
        )
    }

    private func extractRealTitle(from command: String) -> String {
        let lowercase = command.lowercased()

        if lowercase.contains("next") && (lowercase.contains("dev") || lowercase.contains("start")) {
            return "Next.js Dev Server"
        } else if lowercase.contains("vite") && (lowercase.contains("dev") || lowercase.contains("serve")) {
            return "Vite Dev Server"
        } else if lowercase.contains("nuxt") && (lowercase.contains("dev") || lowercase.contains("start")) {
            return "Nuxt.js Server"
        } else if lowercase.contains("react-scripts") && (lowercase.contains("start") || lowercase.contains("test")) {
            return "React Dev Server"
        } else if lowercase.contains("nodemon") {
            return "Nodemon Watcher"
        } else if lowercase.contains("webpack") && lowercase.contains("serve") {
            return "Webpack Dev Server"
        } else if lowercase.contains("webpack") {
            return "Webpack Process"
        } else if lowercase.contains("parcel") {
            return "Parcel Dev Server"
        } else if lowercase.contains("rollup") {
            return "Rollup Bundler"
        } else if lowercase.contains("serve") {
            return "Static Server"
        } else if lowercase.contains("http-server") {
            return "HTTP Server"
        } else if lowercase.contains("live-server") {
            return "Live Server"
        } else if lowercase.contains("browser-sync") {
            return "Browser Sync"
        } else if lowercase.contains("npm exec") {
            return "NPM Package"
        } else if lowercase.contains("npx") {
            return "NPX Tool"
        } else if lowercase.contains("node") && (lowercase.contains("serve") || lowercase.contains("start")) {
            return "Node.js Server"
        } else if lowercase.contains("node") {
            return "Node.js Process"
        } else {
            return "Development Process"
        }
    }

    private func extractRealSubtitle(from command: String) -> String {
        let tokens = command.split(separator: " ")

        // Look for npm/yarn scripts
        if let npmIndex = tokens.firstIndex(where: { $0.lowercased() == "npm" }),
           npmIndex + 1 < tokens.count {
            let script = String(tokens[npmIndex + 1])
            if script.lowercased() != "run" {
                return "npm \(script)"
            } else if npmIndex + 2 < tokens.count {
                return "npm \(String(tokens[npmIndex + 2]))"
            }
        }

        // Look for yarn scripts
        if let yarnIndex = tokens.firstIndex(where: { $0.lowercased() == "yarn" }),
           yarnIndex + 1 < tokens.count {
            let script = String(tokens[yarnIndex + 1])
            return "yarn \(script)"
        }

        return command
    }

    private func extractRealPorts(from command: String) -> [Int] {
        // Simple regex for finding ports
        let pattern = #":(\d{3,5})"# // 3-5 digit ports
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: command, range: NSRange(command.startIndex..., in: command))
        var ports: [Int] = []

        for match in matches.prefix(3) { // Limit to 3 ports max
            if let range = Range(match.range(at: 1), in: command),
               let port = Int(command[range]) {
                ports.append(port)
            }
        }

        return Array(Set(ports)).sorted()
    }

    private func extractRealCategory(from command: String) -> String? {
        let lowercase = command.lowercased()

        if lowercase.contains("next") || lowercase.contains("nuxt") {
            return "Web Framework"
        } else if lowercase.contains("vite") || lowercase.contains("webpack") {
            return "Bundler"
        } else if lowercase.contains("react-scripts") {
            return "Framework"
        } else if lowercase.contains("nodemon") {
            return "Utility"
        }
        return nil
    }

    private func extractRealProjectName(from command: String) -> String? {
        // Try to extract from common patterns
        let patterns = [
            "cd ([^;\\s]+)", // cd /path/to/project
            "node ([^\\s]+)", // node server.js
            "--name ([^\\s]+)", // --name my-project
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
                  let range = Range(match.range(at: 1), in: command) else { continue }
            let name = String(command[range])
            if !name.isEmpty && name.count < 50 { // Reasonable length limit
                return name
            }
        }

        return nil
    }

    private func runCommandSync(_ launchPath: String, arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        return (process.terminationStatus, output)
    }

    private func parseProcessesFromOutput(_ output: String) -> [NodeProcessItemViewModel] {
        let lines = output.split(whereSeparator: \.isNewline)
        var nodeProcesses: [NodeProcessItemViewModel] = []

        for line in lines.prefix(50) { // Limit to prevent memory issues
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]) else { continue }

            let command = String(parts[1])

            if isNodeProcess(command) {
                if let processVM = createProcessViewModel(pid: pid, command: command) {
                    nodeProcesses.append(processVM)
                }
            }
        }

        return Array(nodeProcesses.prefix(10)) // Limit to 10 processes
    }

    private func detectNodeProcesses() async throws -> [NodeProcessItemViewModel] {
        // Use simple ps command to find Node.js processes
        let (status, output) = try await runCommand("/bin/ps", arguments: ["-axo", "pid=,command="])

        guard status == 0 else {
            throw NSError(domain: "ProcessDetection", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "ps command failed"])
        }

        let lines = output.split(whereSeparator: \.isNewline)
        var nodeProcesses: [NodeProcessItemViewModel] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Try to parse PID and command
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2,
                  let pid = Int32(parts[0]) else { continue }

            let command = String(parts[1])

            // Check if it's a Node.js related process
            if isNodeProcess(command) {
                if let processVM = createProcessViewModel(pid: pid, command: command) {
                    nodeProcesses.append(processVM)
                }
            }
        }

        return Array(nodeProcesses.prefix(20)) // Limit to 20 processes
    }

    private func isNodeProcess(_ command: String) -> Bool {
        let lowercase = command.lowercased()

        // Exclude system processes and applications
        guard !lowercase.contains("applications/") &&
              !lowercase.contains("system/library") &&
              !lowercase.contains("contents/macos") &&
              !lowercase.contains("library/") &&
              !lowercase.contains("coreservices") &&
              !lowercase.contains("discord") else { return false }

        // More inclusive Node.js process detection
        return lowercase.hasPrefix("node ") ||
               lowercase.hasPrefix("npm ") ||
               lowercase.hasPrefix("yarn ") ||
               lowercase.hasPrefix("pnpm ") ||
               lowercase.hasPrefix("npx ") ||
               lowercase.contains(" node_modules/.bin/") ||
               lowercase.contains(" npm exec") ||
               lowercase.contains(" react-scripts") ||
               lowercase.contains(" nodemon") ||
               lowercase.contains(" webpack") ||
               lowercase.contains(" vite") ||
               lowercase.contains(" next") ||
               lowercase.contains(" nuxt") ||
               lowercase.contains(" parcel") ||
               lowercase.contains(" rollup") ||
               lowercase.contains("http-server") ||
               lowercase.contains("live-server") ||
               lowercase.contains("browser-sync")
    }

    private func createProcessViewModel(pid: Int32, command: String) -> NodeProcessItemViewModel? {
        // Extract meaningful information from command
        let title = extractTitle(from: command)
        let subtitle = extractSubtitle(from: command)
        let ports = extractPorts(from: command)
        let category = extractCategory(from: command)

        return NodeProcessItemViewModel(
            id: pid,
            pid: pid,
            title: title,
            subtitle: subtitle,
            categoryBadge: category,
            portBadges: ports.map { .init(text: ":\($0)", isLikely: false) },
            infoChips: [
                .init(text: "Node.js", systemImage: "cpu")
            ],
            projectName: extractProjectName(from: command),
            uptimeDescription: "Active",
            startTimeDescription: "Now",
            command: command,
            workingDirectory: nil,
            descriptor: .init(
                name: title,
                displayName: title,
                category: .webFramework,
                runtime: "Node.js",
                packageManager: nil,
                script: subtitle,
                details: nil,
                portHints: ports
            ),
            isStopping: false
        )
    }

    private func extractTitle(from command: String) -> String {
        let lowercase = command.lowercased()

        if lowercase.contains("next") {
            return "Next.js Server"
        } else if lowercase.contains("vite") {
            return "Vite Dev Server"
        } else if lowercase.contains("nuxt") {
            return "Nuxt Server"
        } else if lowercase.contains("react-scripts") {
            return "Create React App"
        } else if lowercase.contains("nodemon") {
            return "Nodemon"
        } else {
            return "Node.js Process"
        }
    }

    private func extractSubtitle(from command: String) -> String {
        let tokens = command.split(separator: " ")
        if let npmIndex = tokens.firstIndex(where: { $0.lowercased() == "npm" }),
           npmIndex + 1 < tokens.count {
            return String(tokens[npmIndex + 1])
        }
        return command
    }

    private func extractPorts(from command: String) -> [Int] {
        let pattern = #":(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let matches = regex.matches(in: command, range: NSRange(command.startIndex..., in: command))
        return matches.compactMap { match in
            if let range = Range(match.range(at: 1), in: command) {
                return Int(command[range])
            }
            return nil
        }
    }

    private func extractCategory(from command: String) -> String? {
        let lowercase = command.lowercased()
        if lowercase.contains("next") || lowercase.contains("vite") || lowercase.contains("nuxt") {
            return "Web Framework"
        } else if lowercase.contains("nodemon") {
            return "Utility"
        }
        return nil
    }

    private func extractProjectName(from command: String) -> String? {
        // Try to extract project name from working directory in command
        if let slashRange = command.range(of: "/", options: .backwards) {
            let afterSlash = String(command[slashRange.upperBound...])
            let components = afterSlash.split(separator: " ")
            if let firstComponent = components.first {
                return String(firstComponent)
            }
        }
        return nil
    }

    private func runCommand(_ launchPath: String, arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus, output)
        } catch {
            throw NSError(domain: "CommandExecution", code: -1, userInfo: [NSLocalizedDescriptionKey: error.localizedDescription])
        }
    }

    func stopProcess(_ pid: Int32) {
        guard pid > 0 else { return }
        guard !stoppingPids.contains(pid) else { return }

        stoppingPids.insert(pid)
        print("🛑 Attempting to slay process \(pid)")

        // Mark as stopping in UI immediately
        if let index = processes.firstIndex(where: { $0.pid == pid }) {
            processes[index] = NodeProcessItemViewModel(
                id: processes[index].id,
                pid: processes[index].pid,
                title: processes[index].title,
                subtitle: processes[index].subtitle,
                categoryBadge: processes[index].categoryBadge,
                portBadges: processes[index].portBadges,
                infoChips: processes[index].infoChips,
                projectName: processes[index].projectName,
                uptimeDescription: processes[index].uptimeDescription,
                startTimeDescription: processes[index].startTimeDescription,
                command: processes[index].command,
                workingDirectory: processes[index].workingDirectory,
                descriptor: processes[index].descriptor,
                isStopping: true
            )
        }

        // Enhanced process termination with verification
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            self.waitForCompleteShutdown(pid: pid)
        }
    }

    private func waitForCompleteShutdown(pid: Int32) {
        let killer = ProcessKiller()

        Task {
            do {
                // Use ProcessKiller for graceful termination
                try await killer.terminate(pid: pid, forceAfter: 1.5)
                print("✅ Process \(pid) termination command sent")

                // Wait for complete shutdown (process + ports)
                let shutdownComplete = await waitForProcessAndPortsShutdown(pid: pid)

                await MainActor.run {
                    self.stoppingPids.remove(pid)

                    if shutdownComplete {
                        // Add a small delay for visual feedback before removing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.processes.removeAll { $0.pid == pid }
                            self.lastUpdated = Date()
                            print("🎉 Process \(pid) and ports fully shutdown - removing from UI")
                        }
                    } else {
                        // Timeout reached, remove anyway but show warning
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.processes.removeAll { $0.pid == pid }
                            self.lastUpdated = Date()
                            self.lastError = "Process \(pid) shutdown incomplete (timeout)"
                            print("⚠️ Process \(pid) removal after timeout")
                        }
                    }
                }

            } catch {
                await MainActor.run {
                    self.stoppingPids.remove(pid)
                    self.lastError = "Failed to terminate process \(pid): \(error.localizedDescription)"
                    print("❌ Failed to terminate process \(pid): \(error)")

                    // Reset stopping state on failure
                    if let index = self.processes.firstIndex(where: { $0.pid == pid }) {
                        self.processes[index] = NodeProcessItemViewModel(
                            id: self.processes[index].id,
                            pid: self.processes[index].pid,
                            title: self.processes[index].title,
                            subtitle: self.processes[index].subtitle,
                            categoryBadge: self.processes[index].categoryBadge,
                            portBadges: self.processes[index].portBadges,
                            infoChips: self.processes[index].infoChips,
                            projectName: self.processes[index].projectName,
                            uptimeDescription: self.processes[index].uptimeDescription,
                            startTimeDescription: self.processes[index].startTimeDescription,
                            command: self.processes[index].command,
                            workingDirectory: self.processes[index].workingDirectory,
                            descriptor: self.processes[index].descriptor,
                            isStopping: false
                        )
                    }
                }
            }
        }
    }

    private func waitForProcessAndPortsShutdown(pid: Int32, timeoutSeconds: TimeInterval = 10.0) async -> Bool {
        let startTime = Date()
        let timeout = Date().addingTimeInterval(timeoutSeconds)

        // Get ports to monitor from the process
        let portsToMonitor = getPortsForProcess(pid: pid)

        while Date() < timeout {
            // Check if process is still running
            let processIsRunning = isProcessRunning(pid: pid)

            // Check if all ports are free
            var allPortsFree = true
            for port in portsToMonitor {
                if !isPortFree(port: port) {
                    allPortsFree = false
                    break
                }
            }

            // If both process and ports are down, we're done!
            if !processIsRunning && allPortsFree {
                let elapsed = Date().timeIntervalSince(startTime)
                print("🎯 Process \(pid) and ports fully shutdown in \(String(format: "%.2f", elapsed))s")
                return true
            }

            // Poll every 500ms
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        print("⏰ Timeout waiting for process \(pid) shutdown")
        return false
    }

    private func isProcessRunning(pid: Int32) -> Bool {
        // Use kill(pid, 0) to check if process exists
        let result = kill(pid, 0)
        return result == 0
    }

    private func isPortFree(port: Int) -> Bool {
        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-i", ":\(port)"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // If output is empty, port is free
            return output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            // If command fails, assume port is free
            return true
        }
    }

    private func getPortsForProcess(pid: Int32) -> [Int] {
        guard let process = processes.first(where: { $0.pid == pid }) else { return [] }

        // Extract ports from port badges
        let portStrings = process.portBadges.map { $0.text }
        var ports: [Int] = []

        for portString in portStrings {
            // Remove ":" prefix and convert to Int
            let cleanPort = portString.replacingOccurrences(of: ":", with: "")
            if let port = Int(cleanPort) {
                ports.append(port)
            }
        }

        return ports
    }

    
    private func bindMonitor() {
        monitor.processesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] processes in
                guard let self else { return }
                self.latestProcesses = processes
                self.lastUpdated = Date()
                self.isLoading = false
                self.publishLatest()
            }
            .store(in: &cancellables)

        monitor.errorsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.lastError = error.localizedDescription
            }
            .store(in: &cancellables)
    }

    
    private func publishLatest() {
        processes = buildViewModels(from: latestProcesses)
    }

    private func buildViewModels(from processes: [NodeProcess]) -> [NodeProcessItemViewModel] {
        let sorted = processes.sorted { lhs, rhs in
            let startInterval = lhs.startTime.timeIntervalSince1970
            let rhsInterval = rhs.startTime.timeIntervalSince1970
            if abs(startInterval - rhsInterval) > 0.001 {
                return startInterval > rhsInterval
            }
            if lhs.uptime != rhs.uptime {
                return lhs.uptime < rhs.uptime
            }
            let lhsPort = lhs.ports.min() ?? Int.max
            let rhsPort = rhs.ports.min() ?? Int.max
            if lhsPort != rhsPort {
                return lhsPort < rhsPort
            }
            if lhs.descriptor.name != rhs.descriptor.name {
                return lhs.descriptor.name.localizedCaseInsensitiveCompare(rhs.descriptor.name) == .orderedAscending
            }
            return lhs.pid < rhs.pid
        }

        return sorted.map { process in
            let title = makeTitle(for: process)
            let commandSummary = makeCommandSummary(for: process)
            let uptimeText = Self.durationFormatter.string(from: process.uptime) ?? "-"
            let startText = Self.relativeFormatter.localizedString(for: process.startTime, relativeTo: Date())
            let isStopping = stoppingPids.contains(process.pid)
            let portBadges = makePortBadges(for: process)
            let infoChips = makeInfoChips(for: process, commandSummary: commandSummary)
            let projectName = makeProjectName(for: process)
            let categoryBadge = process.descriptor == .unknown ? nil : process.descriptor.category.displayName

            return NodeProcessItemViewModel(
                id: process.pid,
                pid: process.pid,
                title: title,
                subtitle: commandSummary,
                categoryBadge: categoryBadge,
                portBadges: portBadges,
                infoChips: infoChips,
                projectName: projectName,
                uptimeDescription: uptimeText,
                startTimeDescription: startText,
                command: process.command,
                workingDirectory: process.workingDirectory,
                descriptor: process.descriptor,
                isStopping: isStopping
            )
        }
    }

    private func makeTitle(for process: NodeProcess) -> String {
        process.descriptor.displayName
    }

    private func makePortBadges(for process: NodeProcess) -> [NodeProcessItemViewModel.PortBadge] {
        var badges = process.ports.map { NodeProcessItemViewModel.PortBadge(text: ":\($0)", isLikely: false) }
        if badges.isEmpty {
            badges = process.descriptor.portHints.map { NodeProcessItemViewModel.PortBadge(text: ":\($0)", isLikely: true) }
        }
        return badges
    }

    private func makeCommandSummary(for process: NodeProcess) -> String {
        if let packageManager = process.descriptor.packageManager, let script = process.descriptor.script {
            return "\(packageManager) \(script)"
        }

        if let script = process.descriptor.script {
            return prettifyToken(script)
        }

        let tokens = CommandParser.tokenize(process.command)
        guard !tokens.isEmpty else { return process.command }

        let prettified = tokens.map { prettifyToken($0) }
        let prefix = prettified.prefix(3)
        return prefix.joined(separator: " ")
    }

    private func makeInfoChips(for process: NodeProcess, commandSummary: String) -> [NodeProcessItemViewModel.InfoChip] {
        var chips: [NodeProcessItemViewModel.InfoChip] = []

        if let runtime = process.descriptor.runtime {
            chips.append(.init(text: runtime, systemImage: "cpu"))
        }

        if let packageManager = process.descriptor.packageManager, let script = process.descriptor.script {
            let text = "\(packageManager) \(script)"
            if text != commandSummary {
                chips.append(.init(text: text, systemImage: "terminal"))
            }
        } else if let script = process.descriptor.script {
            let pretty = prettifyToken(script)
            if pretty != commandSummary {
                chips.append(.init(text: pretty, systemImage: "terminal"))
            }
        }

        if let details = process.descriptor.details {
            chips.append(.init(text: details, systemImage: "info.circle"))
        }

        return Array(chips.prefix(3))
    }

    private func makeProjectName(for process: NodeProcess) -> String? {
        guard let path = process.workingDirectory else { return nil }
        let url = URL(fileURLWithPath: path)
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty {
            return lastComponent
        }
        return url.path
    }

    private func prettifyToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return token }

        // common path expansions
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            let lastComponent = URL(fileURLWithPath: expanded).lastPathComponent
            return lastComponent.isEmpty ? trimmed : lastComponent
        }

        if trimmed.contains("\\") || trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }

        if trimmed.hasPrefix("node_modules/.bin/") {
            return String(trimmed.split(separator: "/").last ?? Substring(trimmed))
        }

        return trimmed
    }

    @MainActor private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    @MainActor private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

  }
