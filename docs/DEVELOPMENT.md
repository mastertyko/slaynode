# Development Documentation

This documentation is for developers who want to contribute to or understand the technical implementation of SlayNode.

## 🛠️ Development

### Project Structure

```
Slaynode/
├── Sources/
│   └── SlayNodeMenuBar/
│       ├── Resources/
│       │   ├── AppIcon.iconset/                    # App icon sources
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

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.