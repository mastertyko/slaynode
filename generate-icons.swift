import AppKit

enum IconError: Error {
    case symbolUnavailable(String)
    case writeFailed(URL)
}

func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
    let newImage = image.copy() as! NSImage
    newImage.lockFocus()
    color.set()
    let rect = NSRect(origin: .zero, size: newImage.size)
    rect.fill(using: .sourceAtop)
    newImage.unlockFocus()
    newImage.isTemplate = false
    return newImage
}

@discardableResult
func writePNG(_ image: NSImage, to url: URL) throws -> URL {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let data = bitmap.representation(using: .png, properties: [.interlaced: false]) else {
        throw IconError.writeFailed(url)
    }
    try data.write(to: url, options: .atomic)
    return url
}

func makeGradientImage(size: CGFloat) throws -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    guard let context = NSGraphicsContext.current?.cgContext else {
        throw IconError.writeFailed(URL(fileURLWithPath: ""))
    }
    context.saveGState()
    defer { context.restoreGState() }
    let colors = [NSColor(calibratedRed: 0.31, green: 0.23, blue: 0.85, alpha: 1.0).cgColor,
                  NSColor(calibratedRed: 0.18, green: 0.82, blue: 0.78, alpha: 1.0).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: []
    )
    let symbolName = "bolt.horizontal.circle.fill"
    guard let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        throw IconError.symbolUnavailable(symbolName)
    }
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.48, weight: .bold)
    guard let configured = baseSymbol.withSymbolConfiguration(config) else {
        throw IconError.symbolUnavailable(symbolName)
    }
    let tinted = tintedImage(configured, color: .white)
    let symbolSize = NSSize(width: size * 0.56, height: size * 0.56)
    let symbolRect = NSRect(
        x: (CGFloat(size) - symbolSize.width) / 2,
        y: (CGFloat(size) - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    tinted.draw(in: symbolRect)
    return image
}

func makeMenuBarIcon(size: CGFloat) throws -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }
    NSColor.clear.set()
    NSBezierPath(rect: NSRect(origin: .zero, size: NSSize(width: size, height: size))).fill()
    let symbolName = "bolt.horizontal.fill"
    guard let baseSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
        throw IconError.symbolUnavailable(symbolName)
    }
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.78, weight: .semibold)
    guard let configured = baseSymbol.withSymbolConfiguration(config) else {
        throw IconError.symbolUnavailable(symbolName)
    }
    let tinted = tintedImage(configured, color: .black)
    let symbolSize = NSSize(width: size * 0.8, height: size * 0.8)
    let symbolRect = NSRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    tinted.draw(in: symbolRect)
    return image
}

let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = projectURL.appending(path: "Sources/SlayNodeMenuBar/Resources/AppIcon.iconset")
let menuBarURL = projectURL.appending(path: "Sources/SlayNodeMenuBar/Resources/Assets.xcassets/MenuBarIcon.imageset")

let sizes: [(filename: String, size: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

let base = try makeGradientImage(size: 1024)

for entry in sizes {
    let targetURL = iconsetURL.appending(path: "\(entry.filename).png")
    let scaled = NSImage(size: NSSize(width: entry.size, height: entry.size))
    scaled.lockFocus()
    base.draw(in: NSRect(origin: .zero, size: NSSize(width: entry.size, height: entry.size)), from: .zero, operation: .copy, fraction: 1.0)
    scaled.unlockFocus()
    try writePNG(scaled, to: targetURL)
}

let menu1x = try makeMenuBarIcon(size: 22)
let menu2x = try makeMenuBarIcon(size: 44)
try writePNG(menu1x, to: menuBarURL.appending(path: "MenuBarIcon.png"))
try writePNG(menu2x, to: menuBarURL.appending(path: "MenuBarIcon@2x.png"))
