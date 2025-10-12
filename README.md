# Slaynode

<div align="center">

![Slaynode Icon](icon-iOS-Default-1024x1024@1x.png)

**A sleek macOS menu bar application for Node.js process management**

[![Swift](https://img.shields.io/badge/Swift-5.9+-FA7343?style=for-the-badge&logo=swift)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple)](https://apple.com/macos)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

## ✨ Features

- 🎯 **Real-time Process Detection** - Automatically detects all running Node.js development servers (npm, yarn, pnpm, npx)
- ⚡ **One-Click Process Management** - Stop development servers instantly with visual feedback
- 🎨 **Enhanced UI** - Large, scroll-free interface showing up to 15+ processes in a single view
- 🔍 **Process Intelligence** - Extracts port numbers, project names, and commands automatically
- 📊 **Live Updates** - Configurable refresh intervals (2-30 seconds) for real-time monitoring
- 🌙 **Menu Bar Integration** - Native macOS menu bar app with beautiful popover interface
- 🔒 **Secure & Private** - All processing happens locally, no network requests or telemetry

## 📸 Screenshots

### Menu Bar Interface
The app appears as a sleek icon in your macOS menu bar:

![Menu Bar Icon](icon-iOS-Default-1024x1024@1x.png)

### Process Management View
Click the menu bar icon to reveal the enhanced process management interface:

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

*Features shown:*
- ✅ Large 380×700px interface for maximum visibility
- ✅ Up to 600px scroll height for 15+ processes
- ✅ Port badges and project information
- ✅ One-click process termination
- ✅ Real-time status updates

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
│       │   ├── AppIcon.iconset/                    # Liquid Glass app icon sources
│       │   ├── Assets.xcassets/                    # Template menu bar glyph + misc assets
│       │   └── icon-iOS-Default-1024x1024@1x.png
│       ├── SlayNodeMenuBarApp.swift               # Main app entry point + AppKit bridge
│       ├── StatusItemController.swift             # Menu bar integration (380×700px popover)
│       ├── ProcessMonitor.swift                   # Process monitoring logic
│       ├── MenuViewModel.swift                    # Dynamic process detection & UI state
│       ├── MenuContentView.swift                  # Enhanced UI with 600px scroll height
│       ├── ProcessKiller.swift                    # Process termination management
│       ├── ProcessClassifier.swift                # Process categorization logic
│       ├── CommandParsing.swift                   # Command parsing and port extraction
│       └── NodeProcess.swift                      # Node.js process data models
├── generate-icons.swift                          # Utility to regenerate app/menu bar icons
├── Tests/                                        # Unit tests
├── build.sh                                     # Build script with LSUIElement=true
├── Package.swift                                # Swift Package Manager
└── README.md                                    # This file
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

Slaynode’s visual identity is now aligned with the macOS 26 “Liquid Glass” aesthetic:

### App Icon
- **Source**: `Sources/SlayNodeMenuBar/Resources/SlayNodeIcon.png` (1024² master artwork)
- **Pipeline**: `swift generate-icons.swift` downscales the master image into the full `.iconset` (16×16 → 512×512 + Retina).
- **Sizes**: 16×16 → 512×512 with @2× Retina variants, plus 1024×1024 marketing size.

### Menu Bar Icon
- **Asset**: `Sources/SlayNodeMenuBar/Resources/Assets.xcassets/MenuBarIcon.imageset`
- **Format**: 22 pt monochrome template PNG (1×/2×) derived from `SlayNodeIcon.png` for automatic system tinting.
- **Regeneration**: `swift generate-icons.swift`

### Icon Refresh Workflow
1. Run `swift generate-icons.swift` to rebuild all PNG variants.
2. (Optional) Export an `.icns` for external use:  
   `iconutil -c icns Sources/SlayNodeMenuBar/Resources/AppIcon.iconset`
3. Build the project (`./build.sh` or `xcodebuild`) to bundle the refreshed assets.
4. Launch the app and confirm tinting/contrast in both light and dark wallpapers.

## 🔧 Configuration

### Preferences

The app stores preferences in:
```bash
~/Library/Containers/com.slaynode.menubar/Data/Library/Preferences/
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

## 🔧 Technical Implementation

### Dynamic Process Detection

The app uses a robust process detection system that identifies Node.js development servers in real-time:

```swift
// Core detection algorithm in MenuViewModel.swift
func refresh() {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -axo pid=,command= | grep -E '^[ ]*[0-9]+ (node |npm |yarn |pnpm |npx )' | head -15"]

        // Process output and extract information
        // - PID extraction
        // - Command parsing for title extraction
        // - Port number detection using regex patterns
        // - Project name inference from working directory
    }
}
```

### Key Features

- **Process Classification**: Automatically categorizes processes as web frameworks, build tools, or package managers
- **Port Detection**: Uses regex patterns to extract port numbers from command arguments
- **Project Inference**: Intelligently extracts project names from command paths and arguments
- **Error Handling**: Comprehensive error handling with fallback mechanisms
- **Threading**: Proper MainActor isolation for UI updates with background processing

### UI Architecture

- **StatusItemController**: Manages NSStatusBar integration and popover display
- **Enhanced Dimensions**: 380×700px popover with 600px scrollable content area
- **Real-time Updates**: Configurable refresh intervals with visual loading states
- **Process Management**: One-click process termination with immediate UI feedback

### Performance Optimizations

- **Efficient Process Listing**: Uses `ps` command with output limiting to prevent system overload
- **Background Processing**: All heavy operations run on background queues
- **UI Threading**: Proper MainActor usage for thread-safe UI updates
- **Memory Management**: Weak references and proper cleanup to prevent memory leaks

## 🧪 Visual Verification Checklist

After regenerating icons or tweaking the Liquid Glass UI, validate the experience on a macOS 26 machine:

1. **Wallpaper Sweep** – Toggle between light, dark, and vivid HDR wallpapers. In *System Settings ▸ Appearance ▸ Menu Bar*, switch between transparent and backed styles and confirm the menu bar glyph remains legible.
2. **Control Center Roundtrip** – Command-drag the Slaynode icon off the menu bar, re-enable it via *System Settings ▸ Control Center ▸ Menu Bar Only Apps*, and verify the app state survives the cycle.
3. **Transparency Toggle** – Enable/disable "Automatically hide and show the menu bar" and observe hover/pressed states, panel shadows, and blur fidelity in both configurations.
4. **Appearance Modes** – Switch between Light, Dark, and Auto; spot-check header/secondary text contrast with Digital Color Meter to keep ≥4.5:1 against underlying wallpapers.
5. **Multi-Display** – Open the extra on a secondary display and ensure the panel shadow and blur adapt to each wallpaper without clipping.
6. **Menu Bar Height Variants** – Increase menu bar size in *System Settings ▸ Accessibility ▸ Display*; the 22 pt template glyph should scale crisply (macOS will pick the 2× asset automatically).

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
- Built with ❤️ for developers worldwide

## 📞 Support

- 📧 Email: support@slaynode.app
- 🐛 Issues: [GitHub Issues](https://github.com/yourusername/slaynode/issues)
- 💬 Discord: [Join our community](https://discord.gg/slaynode)

---

<div align="center">

**Made with ❤️ for the Node.js community**

[⭐ Star this repo](https://github.com/yourusername/slaynode) • [🐛 Report Issues](https://github.com/yourusername/slaynode/issues) • [💬 Start Discussion](https://github.com/yourusername/slaynode/discussions)

</div>
