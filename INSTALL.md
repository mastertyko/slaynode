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
swift test --disable-sandbox

# Build a release bundle
./build.sh release

# Run fast bundle metadata/plist preflight checks
./build.sh --verify-only

# Create CI-style local release artifact names
./release.sh 1.0.0 --build-number 150

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
- Validate that expected runtime commands are visible to `ps`:
  ```bash
  ps -axo pid=,command= | rg '(node|npm|pnpm|yarn|bun|deno|python|ruby|go)' | head -20
  ```
- Validate that service ports are actually listening:
  ```bash
  lsof -nP -iTCP -sTCP:LISTEN | rg '(3000|4173|5173|8000|8080|8787)'
  ```
- Run the built-in port detection samples to confirm parser behavior:
  ```bash
  ./debug-port-detection.sh --samples-only
  ```
- If `lsof` is blocked by OS permissions, grant Terminal or your shell host app permissions in System Settings and retry.

### Menu Bar State Looks Stale After a Process Exits
- Trigger `Refresh` in SlayNode and wait one polling interval.
- Verify that the process is truly gone:
  ```bash
  ps -p <PID_FROM_SLAYNODE> -o pid=,command=
  ```
- If stale rows remain, relaunch SlayNode from terminal and capture logs:
  ```bash
  ./script/build_and_run.sh --verify
  ./script/build_and_run.sh --logs
  ```
- Include the last refresh timestamp and affected PID in bug reports to simplify diagnosis.

### Source Builds Fail
```bash
xcode-select --install
sudo xcode-select --reset
```

### Update Checks Are Missing
- Local builds intentionally disable Sparkle when the feed URL or EdDSA key is not configured.
- `./build.sh --verify-only` now also fails fast if the Sparkle feed URL is not `https://...` or the ED key contains invalid characters, so release metadata problems surface before packaging.
- Local `./release.sh` runs emit a sibling `*-release-metadata.json`, and GitHub releases publish a matching `release-metadata.json` asset with the selected note source and commit provenance.

### Commands Show Sensitive Flags
- SlayNode redacts known secret-bearing arguments before displaying commands in the UI.
- This includes common auth headers, cookies, URL credentials, connection strings, and query parameters such as `token` or `access_token`.
- Source commands still run exactly as launched by the system; only the presentation and local history copy are sanitized.

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
   defaults delete se.slaynode.menubar
   ```

## Getting Help

- [README.md](README.md) for the product overview
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for implementation details
- [GitHub Issues](https://github.com/mastertyko/slaynode/issues) for bug reports
