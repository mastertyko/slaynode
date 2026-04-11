# Development Documentation

This documentation is for developers who want to contribute to or understand the technical implementation of SlayNode.

## Current Product Shape

SlayNode is currently a window-first macOS app built with SwiftUI and SwiftPM.
The primary user experience is the main dashboard window, while the menu bar controller
and popover infrastructure remain in the codebase as supporting or future-facing paths.

## Project Structure

```
SlayNode/
├── Sources/
│   └── SlayNodeMenuBar/
│       ├── SlayNodeMenuBarApp.swift              # App entry point, commands, app activation
│       ├── MainWindowView.swift                  # Main app window shell
│       ├── MenuContentView.swift                 # Shared app content host
│       ├── WindowDashboardView.swift             # Window-first runtime dashboard
│       ├── SettingsView.swift                    # Integrated settings surface
│       ├── AboutWindowView.swift                 # Integrated about surface
│       ├── ProcessMonitoring.swift               # Monitor protocol abstraction
│       ├── ProcessMonitor.swift                  # Process collection and normalization
│       ├── MenuViewModel.swift                   # Runtime UI state and actions
│       ├── ProcessClassifier.swift               # Detection heuristics and role labeling
│       ├── ProcessKiller.swift                   # Stop/kill behavior
│       ├── StatusItemController.swift            # Menu bar integration path
│       └── Resources/                            # App icon, menu bar glyph, bundled resources
├── Tests/SlayNodeMenuBarTests/                   # Unit and integration tests
├── script/build_and_run.sh                       # Official local build/run entry point
├── generate-icons.swift                          # Source-of-truth renderer for brand assets
├── build.sh                                      # Bundle assembly, icon generation, signing
├── release.sh / notarize.sh                      # Packaging and distribution helpers
└── .codex/environments/environment.toml          # Codex Run action wiring
```

### Building from Source

The project uses **Swift Package Manager** for dependency management.

#### Recommended Local Loop
```bash
./script/build_and_run.sh
swift test
```

#### Build Debug Bundle
```bash
./build.sh debug
```

#### Build Release Bundle
```bash
./build.sh release
```

#### Create DMG for Distribution
```bash
./release.sh 1.0
```

#### Notarization Flow
```bash
./notarize.sh 1.0
```

Pushes to `main` automatically create or update the GitHub release that matches the version in `XcodeSupport/Info.plist`.

#### Running Tests
```bash
swift test
```

## Architecture Overview

### App Shell

- `SlayNodeMenuBarApp.swift`
  Owns commands, app activation policy, and startup wiring.
- `MainWindowView.swift`
  Hosts the main dashboard window and in-app auxiliary routing.
- `MenuContentView.swift`
  Bridges shared runtime content between the main window and any legacy popover path.

### Runtime Dashboard

- `WindowDashboardView.swift`
  Provides the window-first UX with search, list/detail split, summary cards, and action surfaces.
- `SettingsView.swift` and `AboutWindowView.swift`
  Render as part of the same app experience instead of detached utility windows.

### Detection Pipeline

- `ProcessMonitor.swift`
  Collects processes, ports, working directories, and parent/child relationships.
- `ProcessClassifier.swift`
  Interprets commands into human-readable runtime roles.
- `MenuViewModel.swift`
  Converts raw process information into dashboard-ready view models and actions.
- `ProcessKiller.swift`
  Handles process termination and user-facing failure cases.

### Supporting Paths

- `StatusItemController.swift`
  Keeps the menu bar entry point alive in the codebase and now uses the generated SlayNode glyph.
- `generate-icons.swift`
  Regenerates both the app icon family and the menu bar template glyph from one geometry source.

## Development Notes

- Local builds regenerate brand assets automatically through [build.sh](../build.sh).
- Sparkle update checks are only active when `SUFeedURL` and `SUPublicEDKey` are valid.
- Crash reporting is optional and depends on build-time configuration.
- The Xcode project remains in the repo, but SwiftPM plus `script/build_and_run.sh` is the primary local workflow.

## 🤝 Contributing

We welcome contributions! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch**
   ```bash
   git checkout -b feature/amazing-feature
   ```
3. **Commit your changes**
   ```bash
   git commit -m "feat: Add amazing feature"
   ```
4. **Push to the branch**
   ```bash
   git push origin feature/amazing-feature
   ```
5. **Open a Pull Request**

### Development Guidelines

- Follow Swift coding conventions
- Write unit tests for new features
- Update documentation whenever product shape or workflow changes
- Keep generated brand assets and their documentation in sync
- Prefer the scripted SwiftPM workflow unless you are specifically validating Xcode behavior

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.
