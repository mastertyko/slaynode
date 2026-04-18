# SlayNode

<div align="center">

<img src="icon-iOS-Default-1024x1024@1x.png" alt="SlayNode icon" width="160">

**A Tahoe-native macOS control room for local services**

[![SwiftPM](https://img.shields.io/badge/SwiftPM-6.2+-FA7343?style=for-the-badge&logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26%2B-000000?style=for-the-badge&logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/mastertyko/slaynode/ci.yml?style=for-the-badge&label=CI)](https://github.com/mastertyko/slaynode/actions)

</div>

SlayNode gives you one place to discover, inspect, and control local services on modern macOS. It unifies live development runtimes, Docker containers, and Homebrew Services into one native dashboard with a fast menu bar entry point, workspace-aware search, and deliberate control actions.

## What You Can Do

- Discover local processes, Docker containers, and Homebrew Services automatically
- Inspect ports, runtime/source, workspace ownership, command context, and health
- Use `Stop`, `Force Stop`, `Restart`, `Open Logs`, and `Open Workspace` when supported
- Search across services, ports, runtimes, and workspaces from the native toolbar
- Restore recent workspaces and window context through local on-device persistence
- Keep everything local on your Mac without sending service metadata anywhere

## Install

1. Download the latest release from [GitHub Releases](https://github.com/mastertyko/slaynode/releases).
2. Drag `SlayNode.app` into `/Applications`.
3. Launch it:

   ```bash
   open /Applications/SlayNode.app
   ```

## Build From Source

**Requirements**
- macOS 26.0 or later
- Xcode 26 or current Command Line Tools with Swift 6.2 support

```bash
git clone https://github.com/mastertyko/slaynode.git
cd slaynode
./script/build_and_run.sh
```

Run the test suite with:

```bash
swift test
```

## Using SlayNode

1. Launch the app and let the dashboard refresh.
2. Choose `All Services` or focus a workspace from the sidebar.
3. Select a service from the center column to inspect it in the detail view and inspector.
4. Use `Stop`, `Force Stop`, `Restart`, `Logs`, or `Open Workspace` depending on what the source supports.
5. Use `Cmd+,` for Settings, the toolbar search field to narrow the list, and the app menu for About.

## Recognition Model

- Frameworks like Vite, Next.js, Bun, Deno, Python, Ruby, and Go services are normalized into one service model.
- Docker containers and Homebrew Services are first-class sources with source-specific actions.
- Working directory, command parsing, ports, health, and dependency heuristics are combined to reduce false positives.
- Sensitive arguments such as API keys and tokens are redacted before commands are shown in the UI.

## Product Shape

- Main window: Tahoe-native `NavigationSplitView` with sidebar, list, detail, and inspector
- Menu bar: fast triage surface backed by the same service graph as the main app
- Persistence: recent workspaces, actions, and window state stored locally with SwiftData
- System integration: App Intents, Spotlight indexing, local notifications, and native window restoration

## Documentation

- [INSTALL.md](INSTALL.md) for installation, source-build, and troubleshooting
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for architecture, release automation, and contributor context
- [docs/ICON_SYSTEM.md](docs/ICON_SYSTEM.md) for the brand asset pipeline

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
