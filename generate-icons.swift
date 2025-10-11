import AppKit

enum IconError: Error {
    case baseImageMissing(URL)
    case writeFailed(URL)
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

func resizedImage(from base: NSImage, to size: CGFloat) -> NSImage {
    let targetSize = NSSize(width: size, height: size)
    let image = NSImage(size: targetSize)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    base.draw(in: NSRect(origin: .zero, size: targetSize),
              from: NSRect(origin: .zero, size: base.size),
              operation: .copy,
              fraction: 1.0,
              respectFlipped: false,
              hints: [NSImageRep.HintKey.interpolation: NSImageInterpolation.high.rawValue])
    image.unlockFocus()
    return image
}

func menuBarTemplate(from base: NSImage, size: CGFloat, insetFraction: CGFloat = 0.08) -> NSImage {
    let targetSize = NSSize(width: size, height: size)
    let image = NSImage(size: targetSize)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let inset = size * insetFraction
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    base.draw(in: rect,
              from: NSRect(origin: .zero, size: base.size),
              operation: .copy,
              fraction: 1.0,
              respectFlipped: false,
              hints: [NSImageRep.HintKey.interpolation: NSImageInterpolation.high.rawValue])
    NSColor.black.set()
    rect.fill(using: .sourceAtop)
    image.unlockFocus()
    image.isTemplate = true
    return image
}

let fileManager = FileManager.default
let projectURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = projectURL.appending(path: "Sources/SlayNodeMenuBar/Resources")
let baseIconURL = resourcesURL.appending(path: "SlayNodeIcon.png")

let iconsetURL = resourcesURL.appending(path: "AppIcon.iconset")
let menuBarURL = resourcesURL.appending(path: "Assets.xcassets/MenuBarIcon.imageset")

guard let baseIcon = NSImage(contentsOf: baseIconURL) else {
    throw IconError.baseImageMissing(baseIconURL)
}

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

for entry in sizes {
    let resized = resizedImage(from: baseIcon, to: entry.size)
    let targetURL = iconsetURL.appending(path: "\(entry.filename).png")
    try writePNG(resized, to: targetURL)
}

let menu1x = menuBarTemplate(from: baseIcon, size: 22)
let menu2x = menuBarTemplate(from: baseIcon, size: 44)
try writePNG(menu1x, to: menuBarURL.appending(path: "MenuBarIcon.png"))
try writePNG(menu2x, to: menuBarURL.appending(path: "MenuBarIcon@2x.png"))
