import AppKit

enum IconError: Error {
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

func brandColor(_ hex: UInt32, alpha: CGFloat = 1.0) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xFF) / 255.0
    let green = CGFloat((hex >> 8) & 0xFF) / 255.0
    let blue = CGFloat(hex & 0xFF) / 255.0
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func canvasImage(size: CGFloat, draw: (CGRect) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    image.unlockFocus()
    return image
}

func rect(center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
}

func fillCircle(center: CGPoint, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: rect(center: center, radius: radius)).fill()
}

func fillDonut(center: CGPoint, outerRadius: CGFloat, innerRadius: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendOval(in: rect(center: center, radius: outerRadius))
    path.appendOval(in: rect(center: center, radius: innerRadius))
    path.windingRule = .evenOdd
    color.setFill()
    path.fill()
}

func strokeCircle(center: CGPoint, radius: CGFloat, lineWidth: CGFloat, color: NSColor) {
    let path = NSBezierPath(ovalIn: rect(center: center, radius: radius))
    path.lineWidth = lineWidth
    color.setStroke()
    path.stroke()
}

func fillCapsule(_ rect: CGRect, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
}

func drawGlow(center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    guard let gradient = NSGradient(
        colorsAndLocations:
            (color.withAlphaComponent(alpha), 0.0),
            (color.withAlphaComponent(alpha * 0.35), 0.55),
            (color.withAlphaComponent(0.0), 1.0)
    ) else {
        return
    }

    gradient.draw(
        fromCenter: center,
        radius: 0,
        toCenter: center,
        radius: radius,
        options: []
    )
}

func drawConnectorSet(in rect: CGRect, accentOpacity: CGFloat) {
    let size = rect.width
    let upperRail = CGRect(
        x: size * 0.35,
        y: size * 0.54,
        width: size * 0.41,
        height: size * 0.062
    )
    let lowerRail = CGRect(
        x: size * 0.37,
        y: size * 0.44,
        width: size * 0.39,
        height: size * 0.062
    )
    let shortRail = CGRect(
        x: size * 0.54,
        y: size * 0.53,
        width: size * 0.16,
        height: size * 0.052
    )

    fillCapsule(upperRail, color: brandColor(0x32446E, alpha: accentOpacity))
    fillCapsule(lowerRail, color: brandColor(0x32446E, alpha: accentOpacity * 0.94))
    fillCapsule(shortRail, color: brandColor(0x1E2432, alpha: accentOpacity * 0.95))
}

func drawPrimaryNode(center: CGPoint, size: CGFloat, color: NSColor) {
    let outerRadius = size * 0.145
    let innerRadius = size * 0.067
    let coreRadius = size * 0.038

    fillCircle(center: center, radius: outerRadius, color: color)
    fillCircle(center: center, radius: innerRadius, color: brandColor(0x111827))
    fillCircle(center: center, radius: coreRadius, color: brandColor(0xF4F5F8))
    strokeCircle(
        center: center,
        radius: outerRadius,
        lineWidth: max(1, size * 0.005),
        color: brandColor(0xAFC2FF, alpha: 0.35)
    )
}

func drawSecondaryNode(center: CGPoint, size: CGFloat, color: NSColor) {
    let outerRadius = size * 0.102
    let innerRadius = size * 0.048
    let coreRadius = size * 0.029

    fillCircle(center: center, radius: outerRadius, color: color)
    fillCircle(center: center, radius: innerRadius, color: brandColor(0x1B2331))
    fillCircle(center: center, radius: coreRadius, color: brandColor(0xF4F5F8))
    strokeCircle(
        center: center,
        radius: outerRadius,
        lineWidth: max(1, size * 0.0045),
        color: brandColor(0xA6FFF3, alpha: 0.28)
    )
}

func drawSignalNode(center: CGPoint, size: CGFloat) {
    let outerRadius = size * 0.085
    let innerRadius = size * 0.034

    fillCircle(center: center, radius: outerRadius, color: brandColor(0xF09A3E))
    fillCircle(center: center, radius: innerRadius, color: brandColor(0xF6F4EF))

    strokeCircle(
        center: center,
        radius: size * 0.120,
        lineWidth: max(1, size * 0.010),
        color: brandColor(0xF3A54B, alpha: 0.20)
    )
    strokeCircle(
        center: center,
        radius: size * 0.150,
        lineWidth: max(1, size * 0.010),
        color: brandColor(0xF3A54B, alpha: 0.10)
    )
}

func makeAppIcon(size: CGFloat) -> NSImage {
    canvasImage(size: size) { canvas in
        let inset = size * 0.02
        let iconRect = canvas.insetBy(dx: inset, dy: inset)
        let cornerRadius = size * 0.21
        let backgroundPath = NSBezierPath(
            roundedRect: iconRect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )

        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()

        let backgroundGradient = NSGradient(
            colors: [
                brandColor(0x171E29),
                brandColor(0x202937)
            ]
        )
        backgroundGradient?.draw(in: iconRect, angle: -28)

        drawGlow(
            center: CGPoint(x: size * 0.28, y: size * 0.77),
            radius: size * 0.36,
            color: brandColor(0x2E6EFF),
            alpha: 0.20
        )
        drawGlow(
            center: CGPoint(x: size * 0.82, y: size * 0.24),
            radius: size * 0.34,
            color: brandColor(0x20C9C7),
            alpha: 0.18
        )

        NSGraphicsContext.restoreGraphicsState()

        backgroundPath.lineWidth = max(1, size * 0.006)
        brandColor(0xFFFFFF, alpha: 0.15).setStroke()
        backgroundPath.stroke()

        drawConnectorSet(in: canvas, accentOpacity: 0.96)
        drawPrimaryNode(
            center: CGPoint(x: size * 0.30, y: size * 0.49),
            size: size,
            color: brandColor(0x3B74E9)
        )
        drawSecondaryNode(
            center: CGPoint(x: size * 0.69, y: size * 0.63),
            size: size,
            color: brandColor(0x31BBC0)
        )
        drawSignalNode(
            center: CGPoint(x: size * 0.68, y: size * 0.38),
            size: size
        )
    }
}

func makeMenuBarTemplate(size: CGFloat) -> NSImage {
    let image = canvasImage(size: size) { canvas in
        let fill = brandColor(0x000000)

        let upperRail = CGRect(
            x: canvas.width * 0.34,
            y: canvas.height * 0.46,
            width: canvas.width * 0.35,
            height: canvas.height * 0.12
        )
        let lowerRail = CGRect(
            x: canvas.width * 0.38,
            y: canvas.height * 0.30,
            width: canvas.width * 0.26,
            height: canvas.height * 0.11
        )

        fillCapsule(upperRail, color: fill)
        fillCapsule(lowerRail, color: fill)

        fillDonut(
            center: CGPoint(x: canvas.width * 0.28, y: canvas.height * 0.46),
            outerRadius: canvas.width * 0.18,
            innerRadius: canvas.width * 0.075,
            color: fill
        )
        fillDonut(
            center: CGPoint(x: canvas.width * 0.73, y: canvas.height * 0.68),
            outerRadius: canvas.width * 0.125,
            innerRadius: canvas.width * 0.050,
            color: fill
        )
        fillDonut(
            center: CGPoint(x: canvas.width * 0.64, y: canvas.height * 0.24),
            outerRadius: canvas.width * 0.105,
            innerRadius: canvas.width * 0.040,
            color: fill
        )
    }

    image.isTemplate = true
    return image
}

let fileManager = FileManager.default
let projectURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = projectURL.appending(path: "Sources/SlayNodeMenuBar/Resources")
let iconsetURL = resourcesURL.appending(path: "AppIcon.iconset")
let menuBarImagesetURL = resourcesURL.appending(path: "Assets.xcassets/MenuBarIcon.imageset")

let masterAppIcon = makeAppIcon(size: 1024)

try writePNG(masterAppIcon, to: resourcesURL.appending(path: "SlayNodeIcon.png"))
try writePNG(masterAppIcon, to: resourcesURL.appending(path: "icon-iOS-Default-1024x1024@1x.png"))
try writePNG(masterAppIcon, to: projectURL.appending(path: "icon-iOS-Default-1024x1024@1x.png"))

let appIconSizes: [(filename: String, size: CGFloat)] = [
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

for entry in appIconSizes {
    try writePNG(makeAppIcon(size: entry.size), to: iconsetURL.appending(path: "\(entry.filename).png"))
}

try writePNG(makeMenuBarTemplate(size: 88), to: resourcesURL.appending(path: "MenuBarIcon.png"))
try writePNG(
    makeMenuBarTemplate(size: 22),
    to: menuBarImagesetURL.appending(path: "MenuBarIcon.png")
)
try writePNG(
    makeMenuBarTemplate(size: 44),
    to: menuBarImagesetURL.appending(path: "MenuBarIcon@2x.png")
)
