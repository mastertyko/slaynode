import Foundation

enum CommandParser {
    struct CommandContext {
        let executable: String
        let tokens: [String]
        let arguments: [String]
        let workingDirectory: String?

        var lowercasedTokens: [String] {
            tokens.map { $0.lowercased() }
        }

        var lowercasedArguments: [String] {
            arguments.map { $0.lowercased() }
        }
    }

    static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaping = false

        for character in command {
            if isEscaping {
                current.append(character)
                isEscaping = false
                continue
            }

            switch character {
            case "\\":
                isEscaping = true
            case "\"":
                if !inSingleQuote {
                    inDoubleQuote.toggle()
                    continue
                }
                current.append(character)
            case "'":
                if !inDoubleQuote {
                    inSingleQuote.toggle()
                    continue
                }
                current.append(character)
            case _ where character.isWhitespace && !inSingleQuote && !inDoubleQuote:
                if !current.isEmpty {
                    tokens.append(current)
                    current.removeAll(keepingCapacity: false)
                }
            default:
                current.append(character)
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }

    static func makeContext(executable: String, tokens: [String], workingDirectory: String?) -> CommandContext {
        CommandContext(
            executable: executable,
            tokens: tokens,
            arguments: Array(tokens.dropFirst()),
            workingDirectory: workingDirectory
        )
    }

    static func descriptor(from context: CommandContext) -> ServerDescriptor {
        ProcessClassifier.classify(context: context)
    }

    static func inferPorts(from tokens: [String]) -> [Int] {
        var collected: Set<Int> = []

        for (index, token) in tokens.enumerated() {
            if let inlinePort = extractInlinePort(from: token) {
                collected.insert(inlinePort)
                continue
            }

            if isPortFlag(token),
               index + 1 < tokens.count,
               let port = extractPortCandidate(from: tokens[index + 1]) {
                collected.insert(port)
                continue
            }

            if token.contains("://"),
               let components = URLComponents(string: token),
               let port = components.port {
                collected.insert(port)
                continue
            }

            if looksLikeHostPort(token),
               let port = extractTrailingPort(from: token) {
                collected.insert(port)
            }
        }

        return collected.sorted()
    }

    static func inferWorkingDirectory(from tokens: [String]) -> String? {
        let tokenPairs = tokens.enumerated()
        for (index, token) in tokenPairs {
            if token == "--cwd" || token == "--dir" || token == "--working-dir" {
                let nextIndex = index + 1
                if nextIndex < tokens.count {
                    return sanitizePath(tokens[nextIndex])
                }
            }

            if token.hasPrefix("--cwd=") {
                let path = String(token.dropFirst(6))
                return sanitizePath(path)
            }

            if token.hasPrefix("--dir=") {
                let path = String(token.dropFirst(6))
                return sanitizePath(path)
            }

            if token.hasPrefix("--working-dir=") {
                let path = String(token.dropFirst(14))
                return sanitizePath(path)
            }
        }

        if let script = firstScriptToken(from: tokens) {
            let expanded = sanitizePath(script)
            if FileManager.default.fileExists(atPath: expanded) {
                return (expanded as NSString).deletingLastPathComponent
            }
        }

        return nil
    }

    static func firstScriptToken(from tokens: [String]) -> String? {
        return tokens.first(where: { token in
            guard !token.hasPrefix("-") else { return false }
            if token.contains("node_modules/.bin") { return true }
            if token.hasSuffix(".js") || token.hasSuffix(".mjs") || token.hasSuffix(".cjs") { return true }
            if token.contains("next") || token.contains("vite") || token.contains("nuxt") { return true }
            return token.contains("/src/") || token.contains("/server/")
        })
    }

    private static func containsKeyword(in tokens: [String], keywords: [String]) -> Bool {
        tokens.contains { token in
            keywords.contains { keyword in token.contains(keyword) }
        }
    }

    private static func sanitizePath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private static func isPortFlag(_ token: String) -> Bool {
        let normalized = token.lowercased()
        return [
            "--port",
            "-p",
            "--inspect",
            "--inspect-brk",
            "--http-port",
            "--https-port"
        ].contains(normalized)
    }

    private static func extractInlinePort(from token: String) -> Int? {
        let patterns = [
            #"^--?(?:port|p)=(.+)$"#,
            #"^--?(?:inspect|inspect-brk)=(.+)$"#,
            #"^-p(\d+)$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: token, range: NSRange(location: 0, length: token.utf16.count)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: token) else {
                continue
            }

            let candidate = String(token[range])
            if let port = extractPortCandidate(from: candidate) {
                return port
            }
        }

        return nil
    }

    private static func extractPortCandidate(from value: String) -> Int? {
        if let directPort = Int(value), isValidPort(directPort) {
            return directPort
        }

        return extractTrailingPort(from: value)
    }

    private static func extractTrailingPort(from value: String) -> Int? {
        guard let candidate = value.split(separator: ":").last,
              let port = Int(candidate),
              isValidPort(port) else {
            return nil
        }

        return port
    }

    private static func looksLikeHostPort(_ token: String) -> Bool {
        guard token.contains(":") else { return false }

        let lowered = token.lowercased()
        return lowered.contains("localhost:") ||
            lowered.contains("127.") ||
            lowered.contains("0.0.0.0:") ||
            lowered.contains("[::") ||
            token.contains("://")
    }

    private static func isValidPort(_ value: Int) -> Bool {
        (1...65_535).contains(value)
    }
}
