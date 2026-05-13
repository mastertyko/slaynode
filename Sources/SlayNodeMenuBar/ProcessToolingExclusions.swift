import Foundation

enum ProcessToolingExclusions {
    static func isExcluded(executable: String, command: String) -> Bool {
        let executableLower = executable.lowercased()
        let executableName = URL(fileURLWithPath: executableLower).lastPathComponent
        let commandLower = command.lowercased()

        if commandFragments.contains(where: commandLower.contains) {
            return true
        }

        if executableNames.contains(executableName) {
            return true
        }

        return executableNameFragments.contains { executableName.contains($0) }
    }

    private static let commandFragments = [
        "/typescript/lib/tsserver.js",
        "/typescript/lib/typingsinstaller.js",
        "typescript-language-server",
        "browser_use.skill_cli.daemon",
        "/node_modules/agent-browser/",
        "/lib/node_modules/agent-browser/",
        "/agent-browser/bin/agent-browser-darwin",
        "agent-browser-darwin-",
        "/node_modules/oh-my-codex/",
        "/oh-my-codex/dist/",
        "/oh-my-codex/src/",
        "/node_modules/oh-my-openagent/",
        "/lib/node_modules/oh-my-openagent/",
        "/node_modules/oh-my-opencode/",
        "/lib/node_modules/oh-my-opencode/",
        "codex-native-hook.js",
        "codex-native-hook",
        "codex-native-pre-post",
        "/.codex/plugins/cache/",
        "gitstatusd",
        "sourcekit-lsp",
        "esbuild --service",
        "esbuild --ping"
    ]

    private static let executableNames = [
        "codex-native-pre-post",
        "codex-native-hook",
        "esbuild",
        "gitstatusd",
        "sourcekit-lsp",
        "tsserver",
        "typescript-language-server"
    ]

    private static let executableNameFragments = [
        "agent-browser-darwin",
        "tsserver"
    ]
}
