# Icon System Documentation

This documentation covers the icon generation and management system used in SlayNode.

## 🎨 Icon System

Slaynode uses a custom sword icon with green-blue gradient design for the app icon and SF Symbols for the menu bar icon.

### App Icon
- **Source**: `Sources/SlayNodeMenuBar/Resources/SlayNodeIcon.png` (1024² master artwork)
- **Pipeline**: `swift generate-icons.swift` downscales the master image into the full `.iconset` (16×16 → 512×512 + Retina).
- **Sizes**: 16×16 → 512×512 with @2× Retina variants, plus 1024×1024 marketing size.

### Menu Bar Icon
- **Implementation**: SF Symbol "staroflife.fill" for reliable template rendering
- **Fallback System**: Multiple icon options for maximum compatibility
- **Format**: System-native SF Symbols with automatic theme adaptation

### Icon Refresh Workflow
1. **Update Master Icon**: Replace `Sources/SlayNodeMenuBar/Resources/SlayNodeIcon.png`
2. **Generate Variants**: Run `swift generate-icons.swift` to rebuild all PNG variants
3. **Build Project**: Run `./build.sh` to bundle the refreshed assets
4. **Test**: Launch app and verify icons in both light and dark mode

### Technical Notes

**Why SF Symbols for Menu Bar:**
- Template rendering issues with custom PNG icons
- System-native reliability and automatic theme adaptation
- Proper scaling across different display densities
- No white/blank icon issues

**Icon Generation Script:**
The `generate-icons.swift` utility handles:
- Resizing master icon to all required sizes
- Creating proper PNG variants with transparency
- Generating both 1x and 2x variants for menu bar
- Ensuring consistent quality across all sizes

### Adding New Icons

1. **App Icon**: Update `SlayNodeIcon.png` with new design
2. **Menu Bar Icon**: Modify SF Symbol selection in `StatusItemController.swift`
3. **Generate**: Run `swift generate-icons.swift` for app icon variants
4. **Test**: Verify icons work in both light and dark modes

## 🎯 Design Guidelines

**App Icon:**
- Use 1024×1024 PNG with transparency
- Include clear visual elements that scale well
- Maintain high contrast for visibility
- Consider both light and dark background compatibility

**Menu Bar Icon:**
- Prefer SF Symbols for reliability
- Ensure template rendering compatibility
- Test across macOS versions
- Verify visibility in both themes