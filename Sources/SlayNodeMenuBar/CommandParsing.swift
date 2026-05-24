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

        if isEscaping {
            current.append("\\")
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
            if let environmentPort = extractPortEnvironmentAssignment(from: token) {
                collected.insert(environmentPort)
                continue
            }

            if let jvmPort = extractJVMPortProperty(from: token) {
                collected.insert(jvmPort)
                continue
            }

            if let inlinePort = extractInlinePort(from: token) {
                collected.insert(inlinePort)
                continue
            }

            if isInlineDefaultInspectFlagWithoutPort(token) {
                collected.insert(9_229)
                continue
            }

            if isDefaultInspectFlag(token) {
                if index + 1 < tokens.count,
                   let port = extractPortCandidate(from: tokens[index + 1]) {
                    collected.insert(port)
                } else {
                    collected.insert(9_229)
                }
                continue
            }

            if isPortFlag(token),
               index + 1 < tokens.count,
               let port = extractPortCandidate(from: tokens[index + 1]) {
                collected.insert(port)
                continue
            }

            if token.contains("://"),
               let port = extractURLPort(from: token) {
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
            if workingDirectoryValueFlags.contains(token) {
                let nextIndex = index + 1
                if nextIndex < tokens.count {
                    return sanitizePath(tokens[nextIndex])
                }
            }

            if let path = inlineWorkingDirectoryPath(from: token) {
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
            if token.hasSuffix(".js") || token.hasSuffix(".mjs") || token.hasSuffix(".cjs") ||
                token.hasSuffix(".ts") || token.hasSuffix(".tsx") || token.hasSuffix(".mts") || token.hasSuffix(".cts") {
                return true
            }
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
        let expanded = (path as NSString).expandingTildeInPath
        let unwrapped = unwrappedQuotedValue(expanded.trimmingCharacters(in: .whitespacesAndNewlines))
        return unwrapped.trimmingCharacters(in: CharacterSet(charactersIn: ",;)"))
    }

    private static let workingDirectoryValueFlags = Set([
        "--cwd",
        "--dir",
        "--working-dir",
        "--root",
        "--project",
        "--workspace",
        "--prefix",
        "-C"
    ])

    private static func inlineWorkingDirectoryPath(from token: String) -> String? {
        for flag in workingDirectoryValueFlags {
            let prefix = "\(flag)="
            if token.hasPrefix(prefix) {
                return String(token.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func isPortFlag(_ token: String) -> Bool {
        let normalized = token.lowercased()
        return [
            "--port",
            "-p",
            "--inspect",
            "--inspect-brk",
            "--inspect-wait",
            "--inspect-port",
            "--http-port",
            "--https-port",
            "--listen",
            "--listen-address",
            "--addr",
            "--address",
            "--bind",
            "--socket"
        ].contains(normalized)
    }

    private static func isDefaultInspectFlag(_ token: String) -> Bool {
        let normalized = token.lowercased()
        return normalized == "--inspect" || normalized == "--inspect-brk" || normalized == "--inspect-wait"
    }

    private static func isInlineDefaultInspectFlagWithoutPort(_ token: String) -> Bool {
        let normalized = token.lowercased()
        let prefixes = ["--inspect=", "--inspect-brk=", "--inspect-wait="]
        guard let prefix = prefixes.first(where: normalized.hasPrefix) else { return false }

        let value = String(token.dropFirst(prefix.count))
        guard extractPortCandidate(from: value) == nil else { return false }
        return !looksLikeExplicitPortValue(value)
    }

    private static func looksLikeExplicitPortValue(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.allSatisfy(\.isNumber) {
            return true
        }

        if portFromHostPortLiteral(trimmed) != nil {
            return true
        }

        return hasExplicitNumericPortSuffix(trimmed)
    }

    private static func extractInlinePort(from token: String) -> Int? {
        let patterns = [
            #"^--?(?:port|p)=(.+)$"#,
            #"^--?(?:inspect|inspect-brk|inspect-wait|inspect-port)=(.+)$"#,
            #"^--?(?:listen|listen-address|addr|address|bind|socket)=(.+)$"#,
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

    private static func extractPortEnvironmentAssignment(from token: String) -> Int? {
        guard let separator = token.firstIndex(of: "=") else { return nil }

        let key = String(token[..<separator])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rawValue = String(token[token.index(after: separator)...])

        guard isPortEnvironmentKey(key) else { return nil }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedValue = unwrappedQuotedValue(trimmedValue)

        if let port = extractPortCandidate(from: normalizedValue) {
            return port
        }

        if let port = extractURLPort(from: normalizedValue) {
            return port
        }

        if let port = extractShellDefaultPort(from: normalizedValue) {
            return port
        }

        // Some shell snippets end values with punctuation (e.g. "PORT=3000,")
        // and should still resolve to the intended port value.
        guard !normalizedValue.contains(":") else { return nil }
        return parsePortPrefix(normalizedValue)
    }

    private static func isPortEnvironmentKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        let parts = key.split { character in
            character == "_" || character == "-"
        }
        return parts.last == "port"
    }

    private static func extractJVMPortProperty(from token: String) -> Int? {
        guard token.hasPrefix("-D"),
              let separator = token.firstIndex(of: "="),
              separator > token.index(token.startIndex, offsetBy: 2) else {
            return nil
        }

        let keyStart = token.index(token.startIndex, offsetBy: 2)
        let key = String(token[keyStart..<separator]).lowercased()
        guard isJVMPortPropertyKey(key) else { return nil }

        let valueStart = token.index(after: separator)
        let rawValue = String(token[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return extractPortCandidate(from: rawValue)
    }

    private static func isJVMPortPropertyKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        let separators = CharacterSet(charactersIn: ".-_")
        let keyParts = key.components(separatedBy: separators).filter { !$0.isEmpty }
        guard let last = keyParts.last else { return false }
        return last == "port"
    }

    private static func extractPortCandidate(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped = unwrappedQuotedValue(trimmed)
        let sanitized = unwrapped.trimmingCharacters(in: CharacterSet(charactersIn: ",;)"))

        if let directPort = Int(sanitized), isValidPort(directPort) {
            return directPort
        }

        return extractTrailingPort(from: sanitized)
    }

    private static func extractTrailingPort(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        return portFromHostPortLiteral(trimmed)
    }

    private static func extractURLPort(from token: String) -> Int? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ",;.)]"))
        guard let components = URLComponents(string: sanitized),
              let port = components.port,
              isValidPort(port) else {
            return nil
        }

        return port
    }

    private static func parsePortPrefix(_ value: String) -> Int? {
        let digits = value.prefix { $0.isNumber }
        guard !digits.isEmpty,
              let port = Int(digits),
              isValidPort(port) else {
            return nil
        }
        return port
    }

    private static func portFromHostPortLiteral(_ value: String) -> Int? {
        if value.hasPrefix("[") {
            guard let bracketEnd = value.lastIndex(of: "]"),
                  bracketEnd < value.index(before: value.endIndex) else {
                return nil
            }
            let colonIndex = value.index(after: bracketEnd)
            guard value[colonIndex] == ":" else { return nil }
            let portStart = value.index(after: colonIndex)
            return parsePortPrefix(String(value[portStart...]))
        }

        let colonCount = value.reduce(into: 0) { count, character in
            if character == ":" {
                count += 1
            }
        }

        // Bare IPv6 literals like "::1" should not be mistaken as host:port.
        guard colonCount == 1, let colonIndex = value.lastIndex(of: ":") else {
            return nil
        }

        let portStart = value.index(after: colonIndex)
        return parsePortPrefix(String(value[portStart...]))
    }

    private static func hasExplicitNumericPortSuffix(_ value: String) -> Bool {
        if value.hasPrefix("["),
           let bracketEnd = value.lastIndex(of: "]"),
           bracketEnd < value.index(before: value.endIndex) {
            let colonIndex = value.index(after: bracketEnd)
            guard value[colonIndex] == ":" else { return false }
            let suffix = value[value.index(after: colonIndex)...]
            return suffix.first?.isNumber == true
        }

        let colonCount = value.reduce(into: 0) { count, character in
            if character == ":" {
                count += 1
            }
        }
        guard colonCount == 1, let colonIndex = value.lastIndex(of: ":") else {
            return false
        }

        let suffix = value[value.index(after: colonIndex)...]
        return suffix.first?.isNumber == true
    }

    private static func unwrappedQuotedValue(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        guard let first = value.first, let last = value.last, first == last else { return value }
        guard first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func extractShellDefaultPort(from value: String) -> Int? {
        guard value.hasPrefix("${"), value.hasSuffix("}") else { return nil }

        let start = value.index(value.startIndex, offsetBy: 2)
        let end = value.index(before: value.endIndex)
        let expression = String(value[start..<end])

        for separator in [":-", ":=", "-", "="] {
            guard let range = expression.range(of: separator) else { continue }
            let candidate = String(expression[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let unwrappedCandidate = unwrappedQuotedValue(candidate)
            return extractPortCandidate(from: unwrappedCandidate)
                ?? extractURLPort(from: unwrappedCandidate)
                ?? parsePortPrefix(unwrappedCandidate)
        }

        return nil
    }

    private static func looksLikeHostPort(_ token: String) -> Bool {
        guard token.contains(":") else { return false }

        let lowered = token.lowercased()
        return lowered.contains("localhost:") ||
            lowered.contains("127.") ||
            lowered.contains("0.0.0.0:") ||
            lowered.contains("[::") ||
            lowered.contains("*:") ||
            token.contains("://") ||
            looksLikeIPv4HostPort(token)
    }

    private static func looksLikeIPv4HostPort(_ token: String) -> Bool {
        guard let colonIndex = token.lastIndex(of: ":") else { return false }
        let rawHost = token[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let host = rawHost.split(separator: "/").last.map(String.init) ?? String(rawHost)
        let octets = host.split(separator: ".")

        guard octets.count == 4 else { return false }

        for octet in octets {
            guard !octet.isEmpty,
                  octet.allSatisfy(\.isNumber),
                  let value = Int(octet),
                  (0...255).contains(value) else {
                return false
            }
        }

        return true
    }

    private static func isValidPort(_ value: Int) -> Bool {
        (1...65_535).contains(value)
    }
}
