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
        let loweredTokens = context.lowercasedTokens
        guard let executor = loweredTokens.first else { return nil }

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

        guard let packageManager = wrappers[executor] else {
            return nil
        }

        let remainingTokens = Array(context.tokens.dropFirst())
        if remainingTokens.isEmpty {
            return nil
        }

        let nestedContext = CommandParser.makeContext(
            executable: remainingTokens.first ?? "",
            tokens: remainingTokens,
            workingDirectory: context.workingDirectory
        )

        if let descriptor = classifyKnownFramework(context: nestedContext) {
            let scriptOverride = extractScriptName(from: context.tokens) ?? descriptor.script
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

        if let scriptName = extractScriptName(from: context.tokens) {
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
        let first = tokens[0].lowercased()
        let second = tokens[1].lowercased()

        if second == "run" || second == "run-script" {
            return tokens.count > 2 ? tokens[2] : nil
        }

        if ["dlx", "exec", "create"].contains(second) {
            return tokens.count > 2 ? tokens[2] : nil
        }

        if first == "bun" && (second == "run" || second == "wip") {
            return tokens.count > 2 ? tokens[2] : nil
        }

        let commonManagers = Set(["npm", "pnpm", "pnpx", "yarn", "yarnx", "bun", "bunx"])
        if commonManagers.contains(first), !second.hasPrefix("-") {
            return tokens[1]
        }

        return nil
    }

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
        if context.lowercasedTokens.contains(where: { $0.contains("deno") }) {
            return "Deno"
        }
        if context.lowercasedTokens.contains(where: { $0.contains("bun") }) {
            return "Bun"
        }
        if context.lowercasedTokens.contains(where: { $0.contains("node") }) {
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
        case storybook
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
            case .storybook: return "Storybook"
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
            case .vite, .webpackDevServer:
                return .bundler
            case .storybook:
                return .componentWorkbench
            case .expo, .reactNative:
                return .mobile
            case .nest, .express, .fastify, .koa:
                return .backend
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
            case .next, .vite, .nuxt, .svelteKit, .remix, .astro, .angular:
                return { tokens in
                    let modes = ["dev", "start", "serve", "preview", "build"]
                    guard let mode = tokens.first(where: { modes.contains($0) }) else { return nil }
                    return "Mode: \(mode.uppercased())"
                }
            case .expo:
                return { tokens in
                    if tokens.contains("start") { return "Mode: START" }
                    if tokens.contains("start:web") { return "Mode: WEB" }
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
            case .storybook: return [6006]
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
        (.next, { tokens in tokens.contains { $0.contains("next") } }),
        (.vite, { tokens in tokens.contains { $0.contains("vite") } }),
        (.nuxt, { tokens in tokens.contains { $0.contains("nuxt") } }),
        (.svelteKit, { tokens in tokens.contains { $0.contains("svelte-kit") || $0.contains("sveltekit") } }),
        (.remix, { tokens in tokens.contains { $0.contains("remix") } }),
        (.astro, { tokens in tokens.contains { $0.contains("astro") } }),
        (.nest, { tokens in tokens.contains { $0.contains("@nestjs/cli") || $0 == "nest" } }),
        (.express, { tokens in tokens.contains { $0.contains("express") } }),
        (.fastify, { tokens in tokens.contains { $0.contains("fastify") } }),
        (.koa, { tokens in tokens.contains { $0.contains("koa") } }),
        (.storybook, { tokens in tokens.contains { $0.contains("storybook") } }),
        (.webpackDevServer, { tokens in tokens.contains { $0.contains("webpack-dev-server") } }),
        (.angular, { tokens in tokens.contains { $0 == "ng" || $0.contains("@angular/cli") } }),
        (.createReactApp, { tokens in tokens.contains { $0.contains("react-scripts") } }),
        (.expo, { tokens in tokens.contains { $0.contains("expo") } }),
        (.reactNative, { tokens in tokens.contains { $0.contains("react-native") || $0.contains("metro") } }),
        (.turbo, { tokens in tokens.contains { $0.contains("turbo") } }),
        (.nx, { tokens in tokens.contains { $0.contains("nx") } }),
        (.tsx, { tokens in tokens.contains { $0.contains("tsx") } }),
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
        if lowered.contains("storybook") { return [6006] }
        if lowered.contains("expo") || lowered.contains("metro") { return [19000, 19006, 8081] }
        if lowered.contains("angular") || lowered == "ng" { return [4200] }
        if lowered.contains("fastify") || lowered.contains("express") || lowered.contains("koa") {
            return [3000, 4000]
        }
        if lowered.contains("react-scripts") { return [3000] }
        if lowered.contains("astro") { return [4321] }
        if lowered.contains("nuxt") { return [3000] }
        if lowered.contains("remix") { return [3000] }
        if lowered.contains("bun") { return [3000] }
        if lowered.contains("deno") { return [8000] }
        return []
    }
}
