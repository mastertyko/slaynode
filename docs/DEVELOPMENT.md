# Development Documentation

This documentation is for developers who want to contribute to or understand the technical implementation of SlayNode.

## Current Product Shape

SlayNode is now a macOS 26-first desktop app built with SwiftUI, Observation, SwiftData, and SwiftPM. The primary experience is a Tahoe-native main window backed by a normalized local service graph, while the menu bar extra, app intents, and system integrations all share the same state and action layer.

## Project Structure

```text
SlayNode/
├── Sources/
│   └── SlayNodeMenuBar/
│       ├── SlayNodeMenuBarApp.swift              # App scenes, commands, settings/about windows, menu bar extra
│       ├── ServiceExperienceView.swift           # Main NavigationSplitView UI, menu bar UI, settings, about
│       ├── ServiceCenterModel.swift              # Shared app state, refresh loop, notifications, Spotlight bridge
│       ├── ServiceProviders.swift                # Discovery providers, control providers, orchestrator, heuristics
│       ├── ManagedServices.swift                 # Normalized service domain model and SwiftData records
│       ├── ServiceHistoryStore.swift             # Recent workspaces, action history, restoration persistence
│       ├── ServiceIntents.swift                  # App Intents / entity definitions
│       ├── UpdateController.swift                # Sparkle/release update integration
│       ├── ProcessMonitor.swift                  # Legacy process monitoring path still used by existing tests/flows
│       ├── MenuViewModel.swift                   # Legacy compatibility UI model for older menu/window paths
│       ├── WindowDashboardView.swift             # Legacy dashboard compatibility layer
│       ├── StatusItemController.swift            # Legacy/AppKit menu bar bridge and glyph loading
│       └── Resources/                            # App icon, menu bar glyph, bundled resources
├── Tests/SlayNodeMenuBarTests/                   # Unit and integration tests
├── script/build_and_run.sh                       # Official local build/run entry point
├── generate-icons.swift                          # Source-of-truth renderer for brand assets
├── build.sh                                      # Bundle assembly, asset checks, signing
├── release.sh / notarize.sh                      # Packaging and distribution helpers
└── .codex/environments/environment.toml          # Local-only Codex Run action wiring (ignored)
```

## Building From Source

The project uses Swift Package Manager for dependency management.

### Recommended Local Loop
```bash
./script/build_and_run.sh
swift test
```

To preserve other running SlayNode instances from different clones, `script/build_and_run.sh` now only stops processes launched from the current bundle path by default. Use `--kill-all` to restore global `pkill` behavior, or `--no-kill` to skip shutdown entirely.

### Build Debug Bundle
```bash
./build.sh debug
```

### Build Release Bundle
```bash
./build.sh release
```

### Refresh Icon Assets
```bash
./build.sh --generate-icons debug
```

### Run Build Preflight Without Rebuilding
```bash
./build.sh --verify-only
```

### Create DMG for Distribution
```bash
./release.sh 1.0
```

### Notarization Flow
```bash
./notarize.sh 1.0
```

Successful CI runs on `main` automatically trigger the GitHub release workflow. Each release now gets:

- the marketing version from `XcodeSupport/Info.plist`
- a unique build number from `GITHUB_RUN_NUMBER`
- a build-specific tag in the form `v<version>-build.<number>`
- release notes generated from the current changelog section or recent commits
- DMG and ZIP assets named with both version and build number

You can also trigger the release workflow manually with `workflow_dispatch` if you need to target a specific ref.

### Running Tests
```bash
swift test --disable-sandbox
```

### Full Local Verification Gate
```bash
./script/full_verification.sh
```

That shared gate runs shell syntax checks, static safety checks, plist linting, `git diff --check`, release-note regression scripts, debug port sample validation, and `swift test --disable-sandbox`.

### Improvement Backlog

See [IMPROVEMENT_BACKLOG.md](IMPROVEMENT_BACKLOG.md) for the current maintenance and hardening backlog found during repo audits.

### Local Diagnostics Helpers
```bash
# Run only one command through port extraction regexes
./debug-port-detection.sh --command "node --inspect-wait=127.0.0.1:9330 app.js"

# Use realistic simulated command lines for manual detection checks (default: 3600s)
./test-servers.sh 120
```

### Troubleshooting Discovery

If the app shows no services, first separate "nothing is running" from "discovery failed":

```bash
./script/full_verification.sh
ps -axo pid=,ppid=,etime=,command= | rg 'node|bun|deno|vite|next|tsx|npm|pnpm'
lsof -nP -iTCP -sTCP:LISTEN | rg 'node|bun|deno'
```

- If `ps` is empty, there may simply be no local runtimes to discover.
- If `ps` shows the process but `lsof` does not show a listener, SlayNode may still surface it as a degraded/watch service when command heuristics match.
- If `ps` and `lsof` both look right but the app stays empty, run `./debug-port-detection.sh --samples-only` to confirm the command-shape fixtures still pass.

If the UI looks stale after a process exits or after a local rebuild:

```bash
./script/build_and_run.sh --no-kill
```

- Use the in-app refresh action once after relaunch to force a clean discovery pass.
- If you are testing multiple local clones, prefer the default scoped shutdown behavior in `script/build_and_run.sh` so one clone does not kill another clone's app instance.
- When debugging a single suspect command, pass it directly to `./debug-port-detection.sh --command ...` before changing parser heuristics.

## Architecture Overview

### App Shell

- `SlayNodeMenuBarApp.swift`
  Owns app scenes, window restoration behavior, commands, activation policy, and the shared model container.
- `ServiceExperienceView.swift`
  Renders the Tahoe-native `NavigationSplitView`, the menu bar surface, settings, and about windows.

### Shared Service Layer

- `ManagedServices.swift`
  Defines `ManagedService`, `ServiceSource`, `ServiceAction`, `WorkspaceIdentity`, and the SwiftData persistence models.
- `ServiceCenterModel.swift`
  Hosts the shared observable app state and bridges discovery, persistence, notifications, and Spotlight.
- `ServiceHistoryStore.swift`
  Persists recent workspaces, actions, and scene/window state.

### Discovery And Control

- `ServiceProviders.swift`
  Defines discovery/control protocols and the actor-based `DiscoveryOrchestrator`.
- `ProcessServiceProvider`
  Discovers local processes and supports `Stop`, `Force Stop`, and workspace/config actions.
- `DockerServiceProvider`
  Discovers containers and supports `Stop`, `Force Stop`, `Restart`, and `Open Logs`.
- `BrewServiceProvider`
  Discovers Homebrew Services and supports `Stop` and `Restart`.

### System Integration

- `ServiceIntents.swift`
  Exposes the normalized service graph to App Intents and Shortcuts.
- `ServiceCenterModel.NotificationCoordinator`
  Emits local notifications for failed actions or worsening health transitions.
- `ServiceCenterModel.SpotlightIndexer`
  Keeps recent workspaces and services searchable through Core Spotlight.

### Legacy Compatibility Paths

- `ProcessMonitor.swift`, `MenuViewModel.swift`, `MenuContentView.swift`, `MainWindowView.swift`, and `WindowDashboardView.swift`
  Remain in the repo to preserve older flows, tests, and comparison surfaces while the new architecture becomes the default.
- `StatusItemController.swift`
  Continues to bridge the generated menu bar asset into AppKit-specific status item paths where needed.
- `generate-icons.swift`
  Regenerates both the app icon family and the menu bar template glyph from one geometry source.

## Development Notes

- Local builds use checked-in brand assets through [build.sh](../build.sh); pass `--generate-icons` when intentionally refreshing generated PNGs.
- Use `./build.sh --verify-only` when you want a fast asset/metadata/plist preflight before a full build or release run.
- Use `./script/full_verification.sh` when you want the same broader gate as CI and release automation before pushing changes.
- The minimum deployment target is now `macOS 26.0`.
- `build.sh` accepts `SLAYNODE_VERSION`, `SLAYNODE_BUILD_NUMBER`, and optional Sparkle metadata overrides so CI/release builds can stamp unique bundle metadata without editing tracked plist files.
- When `DEVELOPER_DIR` is unset and `/Applications/Xcode.app/Contents/Developer` exists, `build.sh` uses that Xcode toolchain so SwiftData and Foundation macro plugins are available from scripted local builds.
- The preferred state model is `@Observable` plus structured concurrency, not `ObservableObject` plus Combine, unless working in legacy compatibility code.
- All user-facing command strings should be sanitized through the shared service model before they reach the UI.
- Sparkle update checks are only active when release automation provides valid feed and EDDSA key metadata at build time.
- Crash reporting is optional and depends on build-time configuration.
- The Xcode project remains in the repo, but SwiftPM plus `script/build_and_run.sh` is the primary local workflow.

## Privacy Boundary For Command Capture

SlayNode only inspects process metadata that is already available locally on the Mac:

- process command lines from `ps`
- listening ports and working directories from `lsof`
- Docker metadata from local `docker` CLI queries
- Homebrew service state from local `brew services` output

That metadata stays on-device. SlayNode does not upload process names, commands, ports, paths, or workspace history to any remote service as part of normal discovery.

Before command text is shown in the UI or persisted into local history, it is sanitized through the shared service model. The sanitizer currently redacts:

- secret-bearing flags such as `--token`, `--api-key`, `--password`, `--client-secret`, and connection-string style arguments
- URL credentials such as `postgres://user:password@host/db`
- sensitive query parameters such as `token`, `access_token`, and `api_key`
- secret-bearing headers such as `Authorization:`, `Cookie:`, `Set-Cookie:`, `X-Api-Key:`, and `Proxy-Authorization:`

The raw process continues running exactly as launched by the user or the system. Redaction only affects presentation and locally persisted UI-facing history.

## Process Control Safety Model

SlayNode favors explainable, scoped process control over blind termination:

- `Stop` attempts a graceful shutdown first and prefers the selected process tree over unrelated system processes.
- `Force Stop` is reserved for cases where a process or its group is no longer responding to graceful termination.
- `Restart` is only offered for sources where SlayNode has a credible restart surface, such as Docker containers and Homebrew Services.

Before destructive local-process actions, the app builds a preview from live `ps` data so the UI can explain:

- whether the selected PID is the group leader or only one member of a larger tree
- which descendants are expected to be affected by the action
- whether live command text drifted from the originally discovered command
- whether only sanitized command differences are present, which should not escalate the warning level

The practical rule is that SlayNode tries to preserve user intent and workspace context:

- package-manager wrappers are promoted so previews describe the framework process users actually care about
- workspace-aware actions prefer the most relevant discovered working directory instead of stale shell defaults
- destructive actions are hidden when the current source cannot support them safely

## Contributing

1. Fork the repository.
2. Create a feature branch.
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. Commit your changes.
   ```bash
   git commit -m "feat: Add amazing feature"
   ```
4. Push to the branch.
   ```bash
   git push origin feature/amazing-feature
   ```
5. Open a pull request.

### Development Guidelines

- Follow Swift coding conventions.
- Write unit tests for new features.
- Update documentation whenever product shape or workflow changes.
- Keep generated brand assets and their documentation in sync.
- Prefer the scripted SwiftPM workflow unless you are specifically validating Xcode behavior.

## License

This project is licensed under the MIT License. See the [LICENSE](../LICENSE) file for details.
