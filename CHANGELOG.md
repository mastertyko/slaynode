# Changelog

All notable changes to SlayNode will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2025-10-12

### ✨ New Features & Improvements

#### Architecture & Code Quality
- **Threading Modernization**: Migrated from DispatchQueue to modern Swift concurrency (Task, async/await)
- **Code Consolidation**: Eliminated ~500+ lines of duplicate code through unified process parsing
- **Error Handling Overhaul**: Implemented comprehensive error type system with localized descriptions
- **Memory Management**: Fixed timer memory leaks and improved resource cleanup

#### Bug Fixes
- **MainActor Warnings**: Fixed all threading warnings by properly isolating UI updates
- **Race Conditions**: Resolved synchronization issues in process termination and port verification
- **Memory Leaks**: Fixed timer cleanup in MenuContentView to prevent memory leaks
- **Process Detection**: Improved robustness of process parsing with better error handling

#### New Features
- **Enhanced Process Categories**: Added support for MCP (Model Context Protocol) tools
- **Better Error Messages**: User-friendly error descriptions with technical details
- **Improved Port Detection**: Multiple regex patterns with framework-specific default ports
- **Comprehensive Logging**: Better debugging information throughout the application

#### Technical Improvements
- **Unified Process Parsing**: Single `parseProcessInfo()` function extracts all process information
- **Standardized Error Types**: `MenuViewModelError` enum with proper error propagation
- **Modern Timer Management**: Task-based timers replacing DispatchSourceTimer
- **Input Validation**: Proper validation for process IDs and port numbers
- **Resource Cleanup**: Automatic cleanup of timers and background tasks

#### Performance
- **Reduced Memory Footprint**: Eliminated duplicate code and improved memory management
- **Faster Process Detection**: Optimized parsing algorithms with single-pass extraction
- **Better Concurrency**: Improved task scheduling and thread utilization
- **Graceful Degradation**: Better error recovery and fallback mechanisms

### 🛠️ Development Improvements

- **Documentation**: Updated technical documentation with modern patterns
- **Code Organization**: Better separation of concerns and more maintainable structure
- **Testing Foundation**: Improved error handling makes testing more reliable
- **Future-Proofing**: Modern Swift patterns ensure long-term maintainability

## [1.1.x] - Previous Versions

### Core Features
- Menu bar integration with popover interface
- Real-time Node.js process detection
- One-click process termination
- Port number detection and display
- Project name inference
- Configurable refresh intervals

---

## Migration Guide

### For Users
No action required - all changes are backward compatible and improve reliability.

### For Developers
- The app now uses modern Swift concurrency patterns
- Error handling has been standardized with new error types
- Process parsing functions have been unified
- Threading model has been simplified with MainActor isolation

### Compatibility
- Internal API changes only - no user-facing breaking changes
- All existing functionality preserved with enhanced reliability