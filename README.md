# SlayNode

<div align="center">

![Slaynode Icon](icon-iOS-Default-1024x1024@1x.png)

**A sleek macOS menu bar application for Node.js process management**

[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?style=for-the-badge&logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

## ✨ What It Does

- 🎯 **Auto-Detects Node.js Servers** - Finds npm, yarn, pnpm, and npx processes automatically
- ⚡ **One-Click Stop** - Instantly stop development servers with visual feedback
- 🎨 **Clean Interface** - Large, scroll-free view showing all your servers
- 🔍 **Smart Details** - Shows port numbers, project names, and commands
- 📊 **Live Updates** - Configurable refresh intervals (2-30 seconds)
- 🌙 **Menu Bar App** - Always accessible from your macOS menu bar
- 🔒 **Private & Secure** - Everything happens locally, no network requests

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

1. **Clone the repository**
   ```bash
   git clone https://github.com/mastertyko/slaynode.git
   cd slaynode
   ```

2. **Build the app**
   ```bash
   ./build.sh
   ```

3. **Launch it**
   ```bash
   open Slaynode.app
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

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Made with ❤️ for the Node.js community**

[⭐ Star this repo](https://github.com/mastertyko/slaynode) • [🐛 Report Issues](https://github.com/mastertyko/slaynode/issues)

</div>