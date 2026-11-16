// Renders the 1024px app icon. Run `./build.sh icon` to rebuild Bundle/AppIcon.icns from it.
// A sibling of the Daylist and Agentwatch icons: the same night gradient, grain and frosted card, in
// pull-request purple. A branch leaves the list and ends in a glowing commit where Daylist has its sun,
// and the card shows a pull request with comments, two to review, and one that's waiting on others.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvasLength = 1024
let purple = 0xA371F7
let amber = 0xFFA94D
let blue = 0x4DA3FF
let trunkX: CGFloat = 300
let context = CGContext(
    data: nil,
    width: canvasLength,
    height: canvasLength,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

// macOS icon grid: an 824pt square with 185pt corners, centered on the 1024pt canvas.
let iconShape = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
drawIconShadow(for: iconShape)
context.saveGState()
context.addPath(iconShape)
context.clip()
drawBackground()
drawBranch()
drawGrain()
drawPullRequestCard()
context.restoreGState()
writePNG(context.makeImage()!, to: CommandLine.arguments[1])

func drawIconShadow(for shape: CGPath) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, alpha: 0.35))
    context.addPath(shape)
    context.setFillColor(color(0x0B0816))
    context.fillPath()
    context.restoreGState()
}

func drawBackground() {
    let backgroundGradient = gradient([(0x43307A, 1), (0x1B1638, 1), (0x0A0815, 1)], locations: [0, 0.55, 1])
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let commitGlow = gradient([(purple, 0.5), (0x7C4DE0, 0.18), (0x7C4DE0, 0)], locations: [0, 0.45, 1])
    context.drawRadialGradient(
        commitGlow,
        startCenter: CGPoint(x: 780, y: 810), startRadius: 0,
        endCenter: CGPoint(x: 780, y: 810), endRadius: 560,
        options: []
    )
}

/// The branch: it rises out of the list's trunk, turns, and ends in a glowing commit.
func drawBranch() {
    let center = CGPoint(x: 772, y: 826)
    context.move(to: CGPoint(x: trunkX, y: 700))
    context.addLine(to: CGPoint(x: trunkX, y: center.y - 56))
    context.addQuadCurve(to: CGPoint(x: trunkX + 56, y: center.y), control: CGPoint(x: trunkX, y: center.y))
    context.addLine(to: center)
    context.setStrokeColor(color(purple, alpha: 0.85))
    context.setLineWidth(16)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()

    let dotRadius: CGFloat = 50
    let dotRect = CGRect(x: center.x - dotRadius, y: center.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 64, color: color(purple, alpha: 0.95))
    context.setFillColor(color(purple))
    context.fillEllipse(in: dotRect)
    context.restoreGState()

    context.saveGState()
    context.addEllipse(in: dotRect)
    context.clip()
    context.drawRadialGradient(
        gradient([(0xEFE4FF, 1), (purple, 1)], locations: [0, 1]),
        startCenter: CGPoint(x: center.x - 14, y: center.y + 16), startRadius: 0,
        endCenter: center, endRadius: dotRadius,
        options: []
    )
    context.restoreGState()
}

/// The same fine grain Daylist's icon uses.
func drawGrain() {
    guard let grainContext = CGContext(
        data: nil,
        width: canvasLength,
        height: canvasLength,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let pixels = grainContext.data?.assumingMemoryBound(to: UInt8.self) else { return }
    for row in 0..<canvasLength {
        for column in 0..<canvasLength {
            let offset = row * grainContext.bytesPerRow + column * 4
            let alpha = UInt8.random(in: 0...22)
            let premultipliedValue = Bool.random() ? alpha : 0
            pixels[offset] = premultipliedValue
            pixels[offset + 1] = premultipliedValue
            pixels[offset + 2] = premultipliedValue
            pixels[offset + 3] = alpha
        }
    }
    context.draw(grainContext.makeImage()!, in: CGRect(x: 0, y: 0, width: canvasLength, height: canvasLength))
}

func drawPullRequestCard() {
    let cardPath = CGPath(roundedRect: CGRect(x: 196, y: 228, width: 632, height: 548), cornerWidth: 72, cornerHeight: 72, transform: nil)

    // Draw the card far off canvas so only its shadow lands, leaving the glass see-through.
    context.saveGState()
    context.setShadow(offset: CGSize(width: -4000, height: -20), blur: 46, color: color(0x000000, alpha: 0.5))
    context.translateBy(x: 4000, y: 0)
    context.addPath(cardPath)
    context.setFillColor(color(0x000000))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(cardPath)
    context.clip()
    context.setFillColor(color(0xFFFFFF, alpha: 0.09))
    context.fill(CGRect(x: 0, y: 0, width: canvasLength, height: canvasLength))
    context.drawLinearGradient(
        gradient([(0xFFFFFF, 0.17), (0xFFFFFF, 0.02)], locations: [0, 1]),
        start: CGPoint(x: 512, y: 776), end: CGPoint(x: 512, y: 228),
        options: []
    )
    context.restoreGState()

    context.addPath(cardPath)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.3))
    context.setLineWidth(3)
    context.strokePath()

    drawTrunk(from: 316, to: 776)
    drawCommentsRow(centerY: 662)
    drawReviewRow(centerY: 544, textEnd: 742)
    drawReviewRow(centerY: 430, textEnd: 660)
    drawWaitingRow(centerY: 316)
}

/// The line the rows hang on, like commits on a branch.
func drawTrunk(from bottom: CGFloat, to top: CGFloat) {
    context.move(to: CGPoint(x: trunkX, y: bottom))
    context.addLine(to: CGPoint(x: trunkX, y: top))
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.28))
    context.setLineWidth(8)
    context.setLineCap(.butt)
    context.strokePath()
}

/// Highlighted the way Daylist highlights its selected task, in the panel's "comments" orange.
func drawCommentsRow(centerY: CGFloat) {
    let highlightPath = CGPath(roundedRect: CGRect(x: 222, y: centerY - 56, width: 580, height: 112), cornerWidth: 36, cornerHeight: 36, transform: nil)
    context.addPath(highlightPath)
    context.setFillColor(color(amber, alpha: 0.18))
    context.fillPath()
    context.addPath(highlightPath)
    context.setStrokeColor(color(amber, alpha: 0.6))
    context.setLineWidth(3)
    context.strokePath()
    drawDot(center: CGPoint(x: trunkX, y: centerY), radius: 28, hex: amber, glow: 0.9)
    drawTextLine(from: 372, to: 714, centerY: centerY, height: 24, alpha: 0.92)
}

func drawReviewRow(centerY: CGFloat, textEnd: CGFloat) {
    drawDot(center: CGPoint(x: trunkX, y: centerY), radius: 26, hex: blue, glow: 0.75)
    drawTextLine(from: 372, to: textEnd, centerY: centerY, height: 24, alpha: 0.8)
}

func drawWaitingRow(centerY: CGFloat) {
    context.setFillColor(color(0x8E8AA6))
    context.fillEllipse(in: CGRect(x: trunkX - 24, y: centerY - 24, width: 48, height: 48))
    drawTextLine(from: 372, to: 604, centerY: centerY, height: 24, alpha: 0.3)
}

func drawDot(center: CGPoint, radius: CGFloat, hex: Int, glow: CGFloat) {
    context.saveGState()
    context.setShadow(offset: .zero, blur: radius * 1.4, color: color(hex, alpha: glow))
    context.setFillColor(color(hex))
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.restoreGState()
}

func drawTextLine(from start: CGFloat, to end: CGFloat, centerY: CGFloat, height: CGFloat, alpha: CGFloat) {
    let rect = CGRect(x: start, y: centerY - height / 2, width: end - start, height: height)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
    context.setFillColor(color(0xFFFFFF, alpha: alpha))
    context.fillPath()
}

func gradient(_ stops: [(hex: Int, alpha: CGFloat)], locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map { stop in color(stop.hex, alpha: stop.alpha) } as CFArray, locations: locations)!
}

func color(_ hex: Int, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func writePNG(_ image: CGImage, to path: String) {
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}
