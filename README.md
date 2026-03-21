# SlayNode

<div align="center">

![Slaynode Icon](icon-iOS-Default-1024x1024@1x.png)

**A sleek macOS menu bar application for Node.js process management**

[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?style=for-the-badge&logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/mastertyko/slaynode/ci.yml?style=for-the-badge&label=CI)](https://github.com/mastertyko/slaynode/actions)

</div>

## ✨ What It Does

- 🎯 **Auto-Detects Node.js Servers** - Finds npm, yarn, pnpm, and npx processes automatically
- ⚡ **One-Click Stop** - Instantly stop development servers with visual feedback
- 🎨 **Clean Interface** - Large, scroll-free view showing all your servers
- 🔍 **Smart Details** - Shows port numbers, project names, and commands
- 📊 **Live Updates** - Configurable refresh intervals (2-30 seconds)
- 🌙 **Menu Bar App** - Always accessible from your macOS menu bar
- 🔒 **Private & Secure** - Everything happens locally, no network requests
- 🛡️ **Robust Error Handling** - Comprehensive error reporting and graceful recovery
- 🚀 **Modern Architecture** - Built with Swift concurrency and memory-safe patterns
- 🔄 **Auto Updates** - Built-in Sparkle integration keeps the app current
- 📡 **Crash Reporting** - Optional Sentry integration for stability insights

## 📸 How It Looks

### Menu Bar
The app appears as a clean icon in your macOS menu bar:

![Menu Bar Icon](icon-iOS-Default-1024x1024@1x.png)

### Process Management
Click the menu bar icon to see your running servers:

```
┌─────────────────────────────────────────────────────┐
│  Development Servers                    Updated now  │
│  8 active servers                                   │
│                                                     │
│  🔵 my-app-server                    :3000  [Stop]  │
│      PID: 12345 • Running • http://localhost:3000   │
│      npm run dev • /Users/username/projects/my-app   │
│                                                     │
│  🔵 api-backend                      :8080  [Stop]  │
│      PID: 12347 • Running • http://localhost:8080   │
│      yarn start • /Users/username/projects/api      │
│                                                     │
│  [Refresh]                                      [Quit] │
└─────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Requirements
- macOS 13.0 or later
- Xcode Command Line Tools
- Swift 5.9+

### Installation

#### 🚀 Easy Installation (Recommended)

1. **Download the DMG**
   - Go to the [Latest Release](https://github.com/mastertyko/slaynode/releases)
   - Download `Slaynode-v1.2.0.dmg`

2. **Install the App**
   ```bash
   # Double-click the DMG file to mount it
   # Drag Slaynode.app to your Applications folder
   ```

3. **Launch SlayNode**
   ```bash
   open /Applications/Slaynode.app
   ```

#### 🔧 Build from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/mastertyko/slaynode.git
   cd slaynode
   ```

2. **Build the app**
   ```bash
   ./build.sh
   ```

3. **Create DMG (optional)**
   ```bash
   ./release.sh 1.2.0
   ```

That's it! 🎉 The app appears in your menu bar and starts monitoring Node.js processes automatically.

## 🔧 How It Works

**Automatic Detection:** SlayNode continuously scans for Node.js development servers running on your system.

**Smart Recognition:** It identifies different types of processes:
- Next.js, Vite, React development servers
- npm, yarn, pnpm, npx processes
- Custom Node.js applications

**One-Click Management:** Click the "Stop" button next to any server to instantly terminate it.

## 🐛 Troubleshooting

**App won't start?**
```bash
# Fix permissions and code sign
chmod +x Slaynode.app/Contents/MacOS/SlayNodeMenuBar
codesign --force --sign - Slaynode.app
```

**Menu bar icon missing?**
- Check Activity Monitor for "SlayNodeMenuBar" process
- Restart the app: `killall SlayNodeMenuBar && open Slaynode.app`

**No servers showing?**
- Make sure Node.js processes are actually running
- Check System Settings > Privacy & Security for app permissions

## 📞 Need Help?

- 🐛 **Report Issues**: [GitHub Issues](https://github.com/mastertyko/slaynode/issues)
- 📖 **Documentation**: Check the `docs/` folder for detailed guides
- 🌐 **Website**: [SlayNode Landing Page](https://mastertyko.github.io/slaynode/)

## 🔧 Development

### Building from Source

```bash
# Clone and build
git clone https://github.com/mastertyko/slaynode.git
cd slaynode
./build.sh

# Run tests
swift test

# Create release DMG
./release.sh 1.3.0
```

### CI/CD Configuration

The project uses GitHub Actions for CI/CD. To enable full release automation with notarization, configure these repository secrets:

| Secret | Description |
|--------|-------------|
| `CERTIFICATE_BASE64` | Base64-encoded Developer ID Application certificate (.p12) |
| `CERTIFICATE_PASSWORD` | Password for the .p12 certificate |
| `SIGNING_IDENTITY` | Full signing identity, e.g., `Developer ID Application: Name (TEAM_ID)` |
| `APPLE_ID` | Your Apple ID email for notarization |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |
| `APPLE_TEAM_ID` | Your 10-character Apple Team ID |
| `SENTRY_DSN` | (Optional) Sentry DSN for crash reporting |

### Sparkle Auto-Update Setup

1. Generate EdDSA keys:
   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

2. Add the public key to `build.sh` (SUPublicEDKey in Info.plist)

3. Store the private key securely for signing releases

4. Update `appcast.xml` with each release

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Made with ❤️ for the Node.js community**

[⭐ Star this repo](https://github.com/mastertyko/slaynode) • [🐛 Report Issues](https://github.com/mastertyko/slaynode/issues)

</div>