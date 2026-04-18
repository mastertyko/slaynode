# Installation Guide

## Release Install

### Requirements
- macOS 26.0 or later

### Install Steps
1. Download the latest release from [GitHub Releases](https://github.com/mastertyko/slaynode/releases).
2. Drag `SlayNode.app` into `/Applications`.
3. Launch it from Finder, Spotlight, or:
   ```bash
   open /Applications/SlayNode.app
   ```

### Verify It Works
1. Launch a local dev service such as:
   ```bash
   npm run dev
   ```
2. Open SlayNode.
3. Confirm the service appears in the center list.
4. Select it and verify that ports, actions, runtime/source, and workspace details show up in the main panel.

Optional additional checks:
- Start a Docker container and confirm it appears with `Restart` and `Logs`.
- Start a Homebrew Service and confirm it is grouped into the same local control surface.

## Build From Source

### Requirements
- macOS 26.0 or later
- Xcode 26 or current Command Line Tools (`xcode-select --install`)

### Recommended Workflow
```bash
git clone https://github.com/mastertyko/slaynode.git
cd slaynode
./script/build_and_run.sh
```

### Useful Commands
```bash
# Run the full test suite
swift test

# Build a release bundle
./build.sh release

# Build, launch, and verify the app process
./script/build_and_run.sh --verify

# Stream app logs
./script/build_and_run.sh --logs
```

## Troubleshooting

### The App Will Not Open
```bash
chmod +x SlayNode.app/Contents/MacOS/SlayNodeMenuBar
codesign --force --sign - SlayNode.app
```

### The App Opens But No Services Are Listed
- Make sure at least one supported local service is running:
  - a development runtime such as Vite, Next.js, Bun, Deno, Python, Ruby, or Go
  - a Docker container
  - a Homebrew Service
- Use the in-app `Refresh` action.
- Check Console.app for `SlayNodeMenuBar` log entries.

### Source Builds Fail
```bash
xcode-select --install
sudo xcode-select --reset
```

### Update Checks Are Missing
- Local builds intentionally disable Sparkle when the feed URL or EdDSA key is not configured.
- This is expected until release metadata is wired correctly.

### Commands Show Sensitive Flags
- SlayNode redacts known secret-bearing arguments before displaying commands in the UI.
- Source commands still run exactly as launched by the system; only the presentation is sanitized.

## Logs

Use one of these approaches:

```bash
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

Or open Console.app and filter on `SlayNodeMenuBar`.

## Uninstall

1. Quit SlayNode from the app menu or by closing the app normally.
2. Remove `SlayNode.app` from `/Applications`.
3. Optionally clear stored local preferences:
   ```bash
   defaults delete com.slaynode.preferences.refreshInterval
   ```

## Getting Help

- [README.md](README.md) for the product overview
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for implementation details
- [GitHub Issues](https://github.com/mastertyko/slaynode/issues) for bug reports
