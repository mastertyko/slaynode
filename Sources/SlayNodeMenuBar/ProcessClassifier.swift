import Foundation

enum ProcessClassifier {
    static func classify(context: CommandParser.CommandContext) -> ServerDescriptor {
        guard !context.tokens.isEmpty else {
            return .unknown
        }

        if let descriptor = classifyPackageManagerWrapper(context: context) {
            return descriptor
        }

        if let descriptor = classifyKnownFramework(context: context) {
            return descriptor
        }

        if let scriptToken = CommandParser.firstScriptToken(from: context.tokens) {
            let name = (scriptToken as NSString).lastPathComponent
            return ServerDescriptor(
                name: name,
                displayName: name,
                category: .utility,
                runtime: runtime(from: context),
                packageManager: nil,
                script: name,
                details: nil,
                portHints: portHints(for: name)
            )
        }

        return ServerDescriptor(
            name: context.executable,
            displayName: context.executable,
            category: .runtime,
            runtime: runtime(from: context),
            packageManager: nil,
            script: nil,
            details: nil,
            portHints: portHints(for: context.executable)
        )
    }

    private static func classifyPackageManagerWrapper(context: CommandParser.CommandContext) -> ServerDescriptor? {
        var effectiveTokens = context.tokens
        var loweredTokens = effectiveTokens.map { $0.lowercased() }
        guard var executor = loweredTokens.first else { return nil }
        var normalizedExecutor = (executor as NSString).lastPathComponent

        if normalizedExecutor == "corepack", effectiveTokens.count > 1 {
            effectiveTokens = Array(effectiveTokens.dropFirst())
            loweredTokens = effectiveTokens.map { $0.lowercased() }
            executor = loweredTokens.first ?? ""
            normalizedExecutor = (executor as NSString).lastPathComponent
        }

        let wrappers: [String: String] = [
            "npm": "npm",
            "npx": "npm",
            "pnpm": "pnpm",
            "pnpx": "pnpm",
            "yarn": "yarn",
            "yarnx": "yarn",
            "bun": "bun",
            "bunx": "bun"
        ]

        guard let packageManager = wrappers[normalizedExecutor] else {
            return nil
        }

        let remainingTokens = Array(effectiveTokens.dropFirst())
        if remainingTokens.isEmpty {
            return nil
        }

        let nestedContext = CommandParser.makeContext(
            executable: remainingTokens.first ?? "",
            tokens: remainingTokens,
            workingDirectory: context.workingDirectory
        )

        if let descriptor = classifyKnownFramework(context: nestedContext) {
            let scriptOverride = extractScriptName(from: effectiveTokens) ?? descriptor.script
            let runtimeValue = descriptor.runtime ?? runtime(from: nestedContext) ?? runtime(from: context)
            return ServerDescriptor(
                name: descriptor.name,
                displayName: descriptor.displayName,
                category: descriptor.category,
                runtime: runtimeValue,
                packageManager: packageManager,
                script: scriptOverride,
                details: descriptor.details,
                portHints: descriptor.portHints
            )
        }

        if let scriptName = extractScriptName(from: effectiveTokens) {
            return ServerDescriptor(
                name: scriptName,
                displayName: scriptName,
                category: .utility,
                runtime: runtime(from: context),
                packageManager: packageManager,
                script: scriptName,
                details: nil,
                portHints: portHints(for: scriptName)
            )
        }

        return ServerDescriptor(
            name: packageManager.capitalized,
            displayName: packageManager.capitalized,
            category: .utility,
            runtime: runtime(from: context),
            packageManager: packageManager,
            script: nil,
            details: nil,
            portHints: portHints(for: packageManager)
        )
    }

    private static func extractScriptName(from tokens: [String]) -> String? {
        guard tokens.count > 1 else { return nil }
        let first = (tokens[0] as NSString).lastPathComponent.lowercased()
        let arguments = Array(tokens.dropFirst())
        guard let commandIndex = firstCommandIndex(in: arguments) else { return nil }
        let command = arguments[commandIndex].lowercased()

        if command == "run" || command == "run-script" {
            return firstScriptArgument(in: arguments, startingAt: commandIndex + 1)
        }

        if ["dlx", "exec", "create"].contains(command) {
            return firstScriptArgument(in: arguments, startingAt: commandIndex + 1)
        }

        if first == "bun", command == "x" {
            return firstScriptArgument(in: arguments, startingAt: commandIndex + 1)
        }

        if first == "bun" && (command == "run" || command == "wip") {
            return firstScriptArgument(in: arguments, startingAt: commandIndex + 1)
        }

        if first == "yarn" && command == "workspace" {
            let script = firstScriptArgument(in: arguments, startingAt: commandIndex + 2)
            if script?.lowercased() == "run" {
                return firstScriptArgument(in: arguments, startingAt: commandIndex + 3)
            }
            return script
        }

        let commonManagers = Set(["npm", "pnpm", "pnpx", "yarn", "yarnx", "bun", "bunx"])
        if commonManagers.contains(first), !command.hasPrefix("-") {
            return arguments[commandIndex]
        }

        return nil
    }

    private static func firstCommandIndex(in arguments: [String]) -> Int? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index].lowercased()
            if optionTakesValue(argument), index + 1 < arguments.count {
                index += 2
                continue
            }
            if isSkippableOption(argument) {
                index += 1
                continue
            }
            return index
        }
        return nil
    }

    private static func firstScriptArgument(in arguments: [String], startingAt startIndex: Int) -> String? {
        var index = startIndex
        while index < arguments.count {
            let argument = arguments[index].lowercased()
            if optionTakesValue(argument), index + 1 < arguments.count {
                index += 2
                continue
            }
            if isSkippableOption(argument) {
                index += 1
                continue
            }
            return arguments[index]
        }
        return nil
    }

    private static func optionTakesValue(_ argument: String) -> Bool {
        packageManagerValueOptions.contains(argument) ||
            CommandParser.isWorkingDirectoryValueFlag(argument)
    }

    private static func isSkippableOption(_ argument: String) -> Bool {
        argument == "--" ||
            packageManagerValueOptions.contains { option in argument.hasPrefix("\(option)=") } ||
            CommandParser.hasInlineWorkingDirectoryValue(argument) ||
            argument.hasPrefix("-")
    }

    private static let packageManagerValueOptions = Set([
        "--workspace",
        "-w",
        "--filter",
        "-f",
        "--package",
        "-p",
        "--config",
        "--userconfig",
        "--registry",
        "--cache",
        "--store-dir"
    ])

    private static func classifyKnownFramework(context: CommandParser.CommandContext) -> ServerDescriptor? {
        let lowered = context.lowercasedTokens

        for (framework, matcher) in frameworkMatchers {
            if matcher(lowered) {
                return descriptor(for: framework, context: context, tokens: context.tokens)
            }
        }

        return nil
    }

    private static func runtime(from context: CommandParser.CommandContext) -> String? {
        if context.lowercasedTokens.contains(where: { tokenMatchesCommand($0, names: ["deno"]) }) {
            return "Deno"
        }
        if context.lowercasedTokens.contains(where: { tokenMatchesCommand($0, names: ["bun", "bunx"]) }) {
            return "Bun"
        }
        if context.lowercasedTokens.contains(where: { tokenMatchesCommand($0, names: ["node", "nodejs"]) }) {
            return "Node.js"
        }
        return nil
    }

    private static func descriptor(for framework: Framework, context: CommandParser.CommandContext, tokens: [String]) -> ServerDescriptor {
        let displayName = framework.displayName
        let runtime = framework.runtime ?? runtime(from: context)
        let details = framework.detailsBuilder?(tokens)

        return ServerDescriptor(
            name: displayName,
            displayName: displayName,
            category: framework.category,
            runtime: runtime,
            packageManager: nil,
            script: framework.defaultScript,
            details: details,
            portHints: framework.portHints
        )
    }

    private typealias FrameworkMatcher = @Sendable ([String]) -> Bool

    private enum Framework {
        case next
        case vite
        case nuxt
        case svelteKit
        case remix
        case astro
        case nest
        case express
        case fastify
        case koa
        case hono
        case adonis
        case nitro
        case tanstackStart
        case storybook
        case parcel
        case webpackDevServer
        case angular
        case createReactApp
        case expo
        case reactNative
        case turbo
        case nx
        case tsx
        case nodemon
        case deno
        case bunServe

        var displayName: String {
            switch self {
            case .next: return "Next.js"
            case .vite: return "Vite"
            case .nuxt: return "Nuxt"
            case .svelteKit: return "SvelteKit"
            case .remix: return "Remix"
            case .astro: return "Astro"
            case .nest: return "NestJS"
            case .express: return "Express"
            case .fastify: return "Fastify"
            case .koa: return "Koa"
            case .hono: return "Hono"
            case .adonis: return "AdonisJS"
            case .nitro: return "Nitro"
            case .tanstackStart: return "TanStack Start"
            case .storybook: return "Storybook"
            case .parcel: return "Parcel"
            case .webpackDevServer: return "Webpack Dev Server"
            case .angular: return "Angular CLI"
            case .createReactApp: return "Create React App"
            case .expo: return "Expo"
            case .reactNative: return "React Native"
            case .turbo: return "Turborepo"
            case .nx: return "Nx"
            case .tsx: return "TSX"
            case .nodemon: return "Nodemon"
            case .deno: return "Deno"
            case .bunServe: return "Bun"
            }
        }

        var runtime: String? {
            switch self {
            case .deno: return "Deno"
            case .bunServe: return "Bun"
            default: return "Node.js"
            }
        }

        var category: ServerDescriptor.Category {
            switch self {
            case .next, .nuxt, .remix, .astro, .angular, .createReactApp, .svelteKit:
                return .webFramework
            case .vite, .parcel, .webpackDevServer:
                return .bundler
            case .storybook:
                return .componentWorkbench
            case .expo, .reactNative:
                return .mobile
            case .nest, .express, .fastify, .koa, .hono, .adonis, .nitro:
                return .backend
            case .tanstackStart:
                return .webFramework
            case .turbo, .nx:
                return .monorepo
            case .tsx, .nodemon:
                return .utility
            case .deno, .bunServe:
                return .runtime
            }
        }

        var defaultScript: String? {
            switch self {
            case .storybook: return "storybook"
            case .turbo: return "dev"
            default: return nil
            }
        }

        var detailsBuilder: (([String]) -> String?)? {
            switch self {
            case .next, .vite, .nuxt, .svelteKit, .remix, .astro, .angular, .tanstackStart, .nitro:
                return { tokens in
                    let modes = ["dev", "start", "serve", "preview", "build"]
                    let normalized = ProcessClassifier.normalizedLifecycleTokens(from: tokens)
                    guard let mode = normalized.first(where: { modes.contains($0) }) else { return nil }
                    return "Mode: \(mode.uppercased())"
                }
            case .expo:
                return { tokens in
                    let normalized = ProcessClassifier.normalizedLifecycleTokens(from: tokens)
                    if normalized.contains("start:web") { return "Mode: WEB" }
                    if normalized.contains("start") { return "Mode: START" }
                    return nil
                }
            default:
                return nil
            }
        }

        var portHints: [Int] {
            switch self {
            case .next: return [3000]
            case .vite: return [5173]
            case .nuxt: return [3000]
            case .svelteKit: return [5173]
            case .remix: return [3000]
            case .astro: return [4321]
            case .nest: return [3000]
            case .express: return [3000, 4000]
            case .fastify: return [3000]
            case .koa: return [3000]
            case .hono: return [3000]
            case .adonis: return [3333]
            case .nitro: return [3000]
            case .tanstackStart: return [3000]
            case .storybook: return [6006]
            case .parcel: return [1234]
            case .webpackDevServer: return [8080, 3000]
            case .angular: return [4200]
            case .createReactApp: return [3000]
            case .expo: return [19000, 19006, 8081]
            case .reactNative: return [8081, 19000]
            case .turbo: return []
            case .nx: return []
            case .tsx: return [3000, 4000]
            case .nodemon: return [3000, 4000]
            case .deno: return [8000]
            case .bunServe: return [3000]
            }
        }
    }

    private static let frameworkMatchers: [(Framework, FrameworkMatcher)] = [
        (.next, { tokens in tokens.contains { tokenMatchesCommand($0, names: ["next"]) } }),
        (.vite, { tokens in tokens.contains { tokenMatchesCommand($0, names: ["vite"]) } }),
        (.nuxt, { tokens in tokens.contains { $0.contains("nuxt") } }),
        (.svelteKit, { tokens in tokens.contains { $0.contains("svelte-kit") || $0.contains("sveltekit") } }),
        (.remix, { tokens in tokens.contains { $0.contains("remix") } }),
        (.astro, { tokens in tokens.contains { $0.contains("astro") } }),
        (.nest, { tokens in tokens.contains { $0.contains("@nestjs/cli") || $0 == "nest" } }),
        (.express, { tokens in tokens.contains { $0.contains("express") } }),
        (.fastify, { tokens in tokens.contains { $0.contains("fastify") } }),
        (.koa, { tokens in tokens.contains { $0.contains("koa") } }),
        (.hono, { tokens in tokens.contains { $0.contains("hono") } }),
        (.adonis, { tokens in tokens.contains { $0.contains("@adonisjs") || $0.contains("adonis") } }),
        (.nitro, { tokens in
            tokens.contains { tokenMatchesCommand($0, names: ["nitro", "h3"]) } ||
                tokens.contains { $0.contains("nitro") || $0.contains("@nitrojs") }
        }),
        (.tanstackStart, { tokens in
            tokens.contains { tokenMatchesCommand($0, names: ["tanstack-start", "vinxi"]) } ||
                tokens.contains { $0.contains("@tanstack/start") || $0.contains("tanstack-start") }
        }),
        (.storybook, { tokens in tokens.contains { $0.contains("storybook") } }),
        (.parcel, { tokens in tokens.contains { tokenMatchesCommand($0, names: ["parcel"]) } }),
        (.webpackDevServer, { tokens in
            tokens.contains { tokenMatchesCommand($0, names: ["webpack-dev-server"]) } ||
                (tokens.contains { tokenMatchesCommand($0, names: ["webpack"]) } && tokens.contains("serve"))
        }),
        (.angular, { tokens in tokens.contains { $0 == "ng" || $0.contains("@angular/cli") } }),
        (.createReactApp, { tokens in tokens.contains { $0.contains("react-scripts") } }),
        (.expo, { tokens in tokens.contains { $0.contains("expo") } }),
        (.reactNative, { tokens in tokens.contains { $0.contains("react-native") || $0.contains("metro") } }),
        (.turbo, { tokens in tokens.contains { tokenMatchesCommand($0, names: ["turbo"]) } }),
        (.nx, { tokens in tokens.contains { tokenMatchesCommand($0, names: ["nx"]) } }),
        (.tsx, { tokens in tokens.contains { tokenMatchesCommand($0, names: ["tsx"]) } }),
        (.nodemon, { tokens in tokens.contains { $0.contains("nodemon") } }),
        (.deno, { tokens in tokens.contains { $0.contains("deno") } }),
        (.bunServe, { tokens in
            let bunToken = tokens.contains { $0 == "bun" || $0.contains("bunx") }
            let serveToken = tokens.contains { $0 == "serve" || $0.contains("serve") }
            return bunToken && serveToken
        })
    ]

    private static func portHints(for name: String) -> [Int] {
        let lowered = name.lowercased()
        if lowered.contains("next") { return [3000] }
        if lowered.contains("vite") { return [5173] }
        if lowered.contains("parcel") { return [1234] }
        if lowered.contains("storybook") { return [6006] }
        if lowered.contains("expo") || lowered.contains("metro") { return [19000, 19006, 8081] }
        if lowered.contains("angular") || lowered == "ng" { return [4200] }
        if lowered.contains("fastify") || lowered.contains("express") || lowered.contains("koa") || lowered.contains("hono") {
            return [3000, 4000]
        }
        if lowered.contains("nitro") || lowered.contains("tanstack-start") {
            return [3000]
        }
        if lowered.contains("adonis") { return [3333] }
        if lowered.contains("react-scripts") { return [3000] }
        if lowered.contains("astro") { return [4321] }
        if lowered.contains("nuxt") { return [3000] }
        if lowered.contains("remix") { return [3000] }
        if lowered.contains("bun") { return [3000] }
        if lowered.contains("deno") { return [8000] }
        return []
    }

    private static func tokenMatchesCommand(_ token: String, names: Set<String>) -> Bool {
        let component = (token.lowercased() as NSString).lastPathComponent
        let stem = (component as NSString).deletingPathExtension
        return names.contains(component) || names.contains(stem)
    }

    private static func normalizedLifecycleTokens(from tokens: [String]) -> [String] {
        tokens.map {
            $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
        }
    }
}
