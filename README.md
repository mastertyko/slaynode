# Slaynode

<div align="center">

![Slaynode Icon](icon-iOS-Default-1024x1024@1x.png)

**A sleek macOS menu bar application for Node.js process management**

[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?style=for-the-badge&logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

## ✨ Features

- 🎯 **Process Monitoring** - Real-time monitoring of all Node.js processes
- ⚡ **Quick Actions** - Kill, restart, or inspect processes with one click
- 🎨 **Beautiful Interface** - Native macOS design with smooth animations
- 🔔 **Smart Notifications** - Get notified about process changes
- 🌙 **Menu Bar Integration** - Always accessible from your menu bar
- 🇸🇪 **Swedish Localization** - Full Swedish language support
- 🔒 **Secure & Private** - No telemetry, your data stays on your Mac

## 📸 Screenshots

### Menu Bar Interface
*(Add screenshot of the menu bar interface)*

### Process Management
*(Add screenshot of process management view)*

## 🚀 Quick Start

### Prerequisites

- macOS 13.0 or later
- Xcode Command Line Tools
- Swift 5.9+

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/slaynode.git
   cd slaynode
   ```

2. **Build the application**
   ```bash
   ./build.sh
   ```

3. **Launch the app**
   ```bash
   open Slaynode.app
   ```

That's it! 🎉 The app will appear in your menu bar and start monitoring Node.js processes automatically.

## 🛠️ Development

### Project Structure

```
Slaynode/
├── Sources/
│   └── SlayNodeMenuBar/
│       ├── Resources/
│       │   ├── AppIcon.iconset/     # App icon (16x16 to 512x512)
│       │   ├── MenuBarIcon.png      # Menu bar icon (22x22)
│       │   └── icon-iOS-Default-1024x1024@1x.png
│       ├── SlayNodeMenuBarApp.swift      # Main app entry point
│       ├── StatusItemController.swift    # Menu bar integration
│       ├── ProcessMonitor.swift          # Process monitoring logic
│       ├── MenuViewModel.swift           # UI state management
│       ├── MenuContentView.swift         # Main UI view
│       └── ...                           # Other components
├── Tests/                                # Unit tests
├── build.sh                            # Build script
├── Package.swift                       # Swift Package Manager
└── README.md                           # This file
```

### Building from Source

The project uses **Swift Package Manager** for dependency management.

#### Development Build
```bash
swift build
```

#### Release Build with .app Bundle
```bash
./build.sh release
```

#### Running Tests
```bash
swift test
```

## 🎨 Icon System

Slaynode features a comprehensive icon system that works seamlessly across macOS:

### App Icon
- **Format**: `.icns` with all required sizes
- **Sizes**: 16x16, 32x32, 128x128, 256x256, 512x512 pixels
- **HiDPI Support**: @2x versions for Retina displays
- **Location**: `Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/`

### Menu Bar Icon
- **Size**: 22x22 pixels (standard macOS menu bar size)
- **Format**: PNG with proper alpha channel
- **Template Support**: Adapts to light/dark mode
- **Location**: `Sources/SlayNodeMenuBar/Resources/MenuBarIcon.png`

### Icon Generation
Icons are automatically processed during build:
1. Original high-resolution icon is resized for different contexts
2. AppIcon.icns is generated from the iconset using `iconutil`
3. Menu bar icon is optimized for template mode
4. All icons are bundled with the application

## 🔧 Configuration

### Preferences

The app stores preferences in:
```bash
~/Library/Containers/se.slaynode.menubar/Data/Library/Preferences/
```

### Supported Commands

- **Refresh**: `⌘R` - Refresh process list
- **Preferences**: `⌘,` - Open settings
- **Quit**: `⌘Q` - Quit application

## 🐛 Troubleshooting

### Common Issues

**Q: App shows "damaged" error**
```bash
# Fix permissions and code sign
chmod +x Slaynode.app/Contents/MacOS/SlayNodeMenuBar
codesign --force --sign - Slaynode.app
```

**Q: Menu bar icon doesn't appear**
- Check that the app is running in Activity Monitor
- Try restarting the app: `killall SlaynodeMenuBar && open Slaynode.app`

**Q: No Node.js processes detected**
- Ensure Node.js processes are actually running
- Check app permissions in System Settings > Privacy & Security

### Logs

Debug logs are available in Console.app:
```
Category: SlayNodeMenuBar
Process: SlayNodeMenuBar
```

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
- Update documentation as needed
- Ensure icons work in both light and dark mode

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Thanks to the Swift community for excellent tools and libraries
- Icon design inspired by modern macOS design principles
- Built with ❤️ in Sweden

## 📞 Support

- 📧 Email: support@slaynode.app
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/slaynode/issues)
- 💬 Discord: [Join our community](https://discord.gg/slaynode)

---

<div align="center">

**Made with ❤️ for the Node.js community**

[⭐ Star this repo](https://github.com/yourusername/slaynode) • [🐛 Report Issues](https://github.com/yourusername/slaynode/issues) • [💬 Start Discussion](https://github.com/yourusername/slaynode/discussions)

</div>
