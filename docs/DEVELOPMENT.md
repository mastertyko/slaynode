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

The app uses a robust process detection system that identifies Node.js development servers in real-time using modern Swift concurrency:

```swift
// Core detection algorithm in MenuViewModel.swift
func refresh() {
    Task { @MainActor [weak self] in
        let processes = await self.performProcessDetection()
        // Update UI on main thread
        self.processes = processes
    }
}

private func performProcessDetection() async -> [NodeProcessItemViewModel] {
    // Uses unified process parsing with comprehensive error handling
    let processInfo = parseProcessInfo(from: command)
    // Extracts title, ports, category, and project name in one pass
}
```

### Key Features

- **Process Classification**: Automatically categorizes processes as web frameworks, build tools, package managers, and MCP tools
- **Unified Process Parsing**: Single `parseProcessInfo()` function extracts all process information in one pass
- **Port Detection**: Uses multiple regex patterns to extract port numbers from command arguments with framework-specific defaults
- **Project Inference**: Intelligently extracts project names from command paths and arguments
- **Comprehensive Error Handling**: Standardized error types with localized descriptions and proper error propagation
- **Modern Threading**: Uses Swift concurrency (Task, async/await) with MainActor isolation for thread-safe UI updates
- **Race Condition Prevention**: Proper synchronization for process termination and port verification
- **Memory Management**: Automatic cleanup of timers and resources to prevent memory leaks

### UI Architecture

- **StatusItemController**: Manages NSStatusBar integration and popover display
- **Enhanced Dimensions**: 380×700px popover with 600px scrollable content area
- **Real-time Updates**: Configurable refresh intervals with visual loading states
- **Process Management**: One-click process termination with immediate UI feedback

### Performance Optimizations

- **Efficient Process Listing**: Uses `ps` command with output limiting to prevent system overload
- **Modern Concurrency**: Task-based background processing replacing DispatchQueue patterns
- **UI Threading**: MainActor isolation for thread-safe UI updates
- **Memory Management**: Weak references, automatic timer cleanup, and proper resource management
- **Code Optimization**: Eliminated ~500+ lines of duplicate code through unified process parsing
- **Error Resilience**: Graceful degradation and comprehensive error recovery mechanisms

### Recent Improvements (v1.2.0)

- **Threading Standardization**: Migrated from DispatchQueue to modern Swift concurrency
- **Error Handling Enhancement**: Implemented comprehensive error type system with localized descriptions
- **Code Consolidation**: Unified duplicate process parsing functions into single, maintainable solution
- **Race Condition Fixes**: Solved synchronization issues in process termination and port verification
- **Memory Leak Prevention**: Fixed timer cleanup issues and improved resource management
- **Architecture Improvements**: Better separation of concerns and more maintainable code structure

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