# SlayNode

<div align="center">

<img src="icon-iOS-Default-1024x1024@1x.png" alt="SlayNode icon" width="160">

**A focused macOS desktop app for local Node.js runtime control**

[![SwiftPM](https://img.shields.io/badge/SwiftPM-6.2+-FA7343?style=for-the-badge&logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/mastertyko/slaynode/ci.yml?style=for-the-badge&label=CI)](https://github.com/mastertyko/slaynode/actions)

</div>

SlayNode gives you one place to see what local JavaScript runtimes are running, which ports they use, what workspace they belong to, and how to stop the right thing without guessing.

## What You Can Do

- Detect local JavaScript and Node.js development processes automatically
- Inspect ports, command context, runtime role, and workspace details
- Stop runtimes safely with `Slay`
- Jump straight into the owning project with `Open Folder`
- Keep everything local on your Mac without sending process data anywhere

## Install

1. Download the latest release from [GitHub Releases](https://github.com/mastertyko/slaynode/releases).
2. Drag `SlayNode.app` into `/Applications`.
3. Launch it:

   ```bash
   open /Applications/SlayNode.app
   ```

## Build From Source

**Requirements**
- macOS 13.0 or later
- Xcode Command Line Tools

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
2. Select a runtime from the left column.
3. Review its ports, command, role, and workspace in the detail pane.
4. Use `Slay`, `Open Folder`, or `Copy Command` depending on what you need.
5. Use `Cmd+,` for Settings and the app menu for About.

## Recognition Model

- Frameworks like Vite, Next.js, and TSX-based runtimes are recognized directly.
- Package-manager wrappers like `npm run dev` and `pnpm dev` are collapsed into clearer runtime rows.
- Working directory, command parsing, ports, and child-process promotion are combined to reduce false positives.

## Documentation

- [INSTALL.md](INSTALL.md) for installation, source-build, and troubleshooting
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for architecture, release automation, and contributor context
- [docs/ICON_SYSTEM.md](docs/ICON_SYSTEM.md) for the brand asset pipeline

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
