# Installation Guide

## Quick Install

### Prerequisites
- macOS 13.0 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+

### Step 1: Clone the Repository
```bash
git clone https://github.com/mastertyko/slaynode.git
cd slaynode
```

### Step 2: Build the Application
```bash
# Build and create .app bundle
./build.sh
```

### Step 3: Launch the App
```bash
# Method 1: Double-click in Finder
open Slaynode.app

# Method 2: Launch from command line
open Slaynode.app
```

The app will appear in your menu bar as a small icon and start monitoring Node.js processes automatically.

## Manual Build Instructions

If you prefer to build manually or need to debug:

### Development Build
```bash
# Build without creating .app bundle
swift build
```

### Debug Build
```bash
# Build with debug symbols
swift build -c debug
```

### Release Build
```bash
# Build optimized release
swift build -c release
```

## Verification

### Check Installation
1. Look for the SlayNode icon in your menu bar
2. Click the icon to see the process list
3. Verify it shows running Node.js processes

### Test Functionality
1. Start a Node.js server:
   ```bash
   npm run dev
   # or
   yarn start
   # or
   node server.js
   ```

2. Click the SlayNode menu bar icon
3. Verify your server appears in the list
4. Test the Stop button functionality

## Troubleshooting

### Common Issues

**"App is damaged" error**
```bash
# Fix permissions and code sign
chmod +x Slaynode.app/Contents/MacOS/SlayNodeMenuBar
codesign --force --sign - Slaynode.app
```

**"Menu bar icon doesn't appear"**
- Check Activity Monitor for "SlayNodeMenuBar" process
- Restart the app:
  ```bash
  killall SlayNodeMenuBar && open Slaynode.app
  ```

**"No processes detected"**
- Ensure Node.js processes are actually running
- Check app permissions in System Settings > Privacy & Security
- Try manual refresh by clicking the Refresh button

**Build fails with Xcode errors**
```bash
# Install Xcode Command Line Tools
xcode-select --install

# If that doesn't work, try:
sudo xcode-select --reset
```

### Logs and Debugging

View debug logs in Console.app:
1. Open Console.app
2. Filter for "SlayNodeMenuBar" in the search bar
3. Look for process detection logs and error messages

### Clean Reinstall

If you experience persistent issues:

```bash
# Remove the app
rm -rf Slaynode.app

# Clean build artifacts
swift package clean

# Rebuild
./build.sh
```

## Permissions

The app requires minimal permissions:
- **Process Monitoring**: Reads process list (built into macOS)
- **Process Termination**: Stops processes you own
- **No Network Access**: All processing happens locally
- **No File System Access**: Only reads process information

## Auto-Start (Optional)

To make SlayNode launch automatically on login:

1. Open **System Settings** > **General** > **Login Items**
2. Click the `+` button
3. Navigate to and select `Slaynode.app`
4. Ensure it's enabled in the login items list

## Uninstall

To completely remove SlayNode:

1. Quit the app: Right-click menu bar icon > Quit
2. Remove from Login Items (if added)
3. Delete the app: `rm -rf Slaynode.app`
4. Remove preferences (optional):
   ```bash
   rm -rf ~/Library/Containers/com.slaynode.menubar
   ```

## Getting Help

- 📧 **Issues**: [GitHub Issues](https://github.com/mastertyko/slaynode/issues)
- 📖 **Documentation**: [README.md](README.md)
- 🔧 **Debug Logs**: Check Console.app for "SlayNodeMenuBar"

---

**Need help?** Open an issue on GitHub and include:
- macOS version
- What you were trying to do
- Any error messages from Console.app