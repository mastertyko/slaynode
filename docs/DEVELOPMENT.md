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
└── .codex/environments/environment.toml          # Codex Run action wiring
```

## Building From Source

The project uses Swift Package Manager for dependency management.

### Recommended Local Loop
```bash
./script/build_and_run.sh
swift test
```

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
swift test
```

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
- The minimum deployment target is now `macOS 26.0`.
- `build.sh` accepts `SLAYNODE_VERSION`, `SLAYNODE_BUILD_NUMBER`, and optional Sparkle metadata overrides so CI/release builds can stamp unique bundle metadata without editing tracked plist files.
- When `DEVELOPER_DIR` is unset and `/Applications/Xcode.app/Contents/Developer` exists, `build.sh` uses that Xcode toolchain so SwiftData and Foundation macro plugins are available from scripted local builds.
- The preferred state model is `@Observable` plus structured concurrency, not `ObservableObject` plus Combine, unless working in legacy compatibility code.
- All user-facing command strings should be sanitized through the shared service model before they reach the UI.
- Sparkle update checks are only active when release automation provides valid feed and EDDSA key metadata at build time.
- Crash reporting is optional and depends on build-time configuration.
- The Xcode project remains in the repo, but SwiftPM plus `script/build_and_run.sh` is the primary local workflow.

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
