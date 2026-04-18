# Icon System Documentation

This documentation covers the brand asset pipeline used in SlayNode.

## Icon System

SlayNode uses one shared source of truth for its icon family: `generate-icons.swift`.
The script renders the dock/app icon and the menu bar glyph from the same control-node
geometry, then writes the generated PNG assets back into `Sources/SlayNodeMenuBar/Resources`.

## Source Of Truth

- `generate-icons.swift`
  This is the canonical renderer for the brand mark.
- `Sources/SlayNodeMenuBar/Resources/SlayNodeIcon.png`
  Generated 1024x1024 app icon master used for previews and marketing.
- `Sources/SlayNodeMenuBar/Resources/AppIcon.iconset/*`
  Generated dock/app icon variants used to build `AppIcon.icns`.
- `Sources/SlayNodeMenuBar/Resources/MenuBarIcon.png`
  Generated high-resolution template glyph used by `StatusItemController`.
- `Sources/SlayNodeMenuBar/Resources/Assets.xcassets/MenuBarIcon.imageset/*`
  Generated 1x/2x template assets kept in sync for Xcode-facing workflows.
- `icon-iOS-Default-1024x1024@1x.png`
  Generated marketing/docs export kept in sync with the current app icon.

## Visual Model

- App icon
  Midnight graphite container with cobalt, teal, and amber runtime nodes.
- Menu bar glyph
  Simplified monochrome version of the same network, without the background tile.

The current icon set is tuned to sit comfortably inside the macOS 26 visual language:
cleaner silhouettes, calmer contrast, and a glyph that still reads clearly against
Liquid Glass toolbars and menu bar treatments.

The menu bar glyph is intentionally not a flattened version of the full app icon.
Template rendering in the macOS menu bar discards color, so the glyph has to be
optically simpler and heavier than the dock icon to stay legible at 16-22 px.

## Workflow

1. Edit the geometry or palette in `generate-icons.swift`.
2. Run `swift generate-icons.swift` to refresh the generated assets.
3. Run `./build.sh` to rebuild the app bundle and `AppIcon.icns`.
4. Verify the icon in Dock, About, and menu bar contexts.

`./build.sh` now regenerates brand assets automatically before building, so
normal local builds stay in sync with the renderer.

## Technical Notes

- `StatusItemController.swift` loads the generated `MenuBarIcon.png` and marks it
  as a template image for proper macOS tinting and highlight behavior.
- The menu bar glyph avoids gradients, glows, and background plates because those
  details collapse in template rendering.
- Repo URLs and bundle identifiers remain lowercase (`slaynode`) even though the
  user-facing product name is `SlayNode`.

## Design Constraints

- Prefer 2-3 bold anchor shapes.
- Preserve generous negative space in the menu bar glyph.
- Keep small-scale strokes optically thicker than the dock icon equivalent.
- Treat generated PNGs as build artifacts, not the primary design source.
