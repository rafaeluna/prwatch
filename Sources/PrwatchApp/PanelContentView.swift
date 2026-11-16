import AppKit

private let panelCornerRadius: CGFloat = 16

/// Layers, back to front: glass or blur, a clipped container holding the texture and the list, and the resize grip.
/// It also reports when the pointer enters or leaves, which switches between the two looks.
@MainActor
final class PanelContentView: NSView {
    var onPointerInsideChange: ((Bool) -> Void)?
    private let backgroundView = BackgroundView()
    private let clipView = NSView()
    private let textureView = TextureView()
    private let resizeGrip = ResizeGripView()

    init(content: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: PanelController.defaultWidth, height: 200))
        clipView.wantsLayer = true
        clipView.layer?.cornerRadius = panelCornerRadius
        clipView.layer?.cornerCurve = .continuous
        clipView.layer?.masksToBounds = true
        clipView.layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor

        fill(self, with: backgroundView)
        fill(self, with: clipView)
        fill(clipView, with: textureView)
        fill(clipView, with: content)
        resizeGrip.frame = NSRect(x: bounds.maxX - 18, y: 0, width: 18, height: 18)
        resizeGrip.autoresizingMask = [.minXMargin, .maxYMargin]
        addSubview(resizeGrip)
        // Always active, because the panel is rarely the key window of an active app.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func apply(_ look: PanelLook, texture: TexturePattern, textureIntensity: Double) {
        backgroundView.apply(look)
        textureView.pattern = texture
        textureView.alphaValue = textureIntensity
        clipView.layer?.borderWidth = look.background == .glass ? 0 : 1
        window?.invalidateShadow()
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerInsideChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerInsideChange?(false)
    }

    private func fill(_ container: NSView, with subview: NSView) {
        subview.frame = container.bounds
        subview.autoresizingMask = [.width, .height]
        container.addSubview(subview)
    }
}

@MainActor
final class BackgroundView: NSView {
    private var style: PanelBackground?
    private var effectView: NSView?
    private let shadeView = NSView()

    init() {
        super.init(frame: .zero)
        shadeView.wantsLayer = true
        shadeView.layer?.cornerRadius = panelCornerRadius
        shadeView.layer?.cornerCurve = .continuous
        shadeView.frame = bounds
        shadeView.autoresizingMask = [.width, .height]
        addSubview(shadeView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Darkness and tint go in a layer above the effect, not in the glass's own tint, because macOS
    /// draws a tinted glass lighter when its window isn't focused.
    func apply(_ look: PanelLook) {
        if look.background != style {
            replaceEffectView(for: look.background)
        }
        if let glassView = effectView as? NSGlassEffectView {
            glassView.style = look.glassStyle == .clear ? .clear : .regular
        }
        if let blurView = effectView as? AdjustableBlurView {
            blurView.blurRadius = look.blurRadius
        }
        shadeView.layer?.backgroundColor = overlayColor(for: look).cgColor
    }

    private func replaceEffectView(for style: PanelBackground) {
        effectView?.removeFromSuperview()
        effectView = makeEffectView(for: style)
        if let effectView {
            effectView.frame = bounds
            effectView.autoresizingMask = [.width, .height]
            addSubview(effectView, positioned: .below, relativeTo: shadeView)
        }
        self.style = style
    }

    private func makeEffectView(for style: PanelBackground) -> NSView? {
        switch style {
        case .glass:
            let glassView = NSGlassEffectView()
            glassView.cornerRadius = panelCornerRadius
            return glassView
        case .blur:
            let blurView = AdjustableBlurView()
            blurView.material = .hudWindow
            blurView.blendingMode = .behindWindow
            blurView.state = .active
            blurView.maskImage = roundedMask()
            return blurView
        case .solid:
            return nil
        }
    }

    /// Darkness and tint as one color: the tint laid over black at the darkness level.
    /// Solid has no darkness, so its tint mixes straight into the base color.
    private func overlayColor(for look: PanelLook) -> NSColor {
        if look.background == .solid {
            let solidBase = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
            return solidBase.blended(withFraction: look.tintStrength, of: look.tint.color) ?? solidBase
        }
        let alpha = look.tintStrength + look.darkness * (1 - look.tintStrength)
        guard alpha > 0 else { return .clear }
        let tintShare = look.tintStrength / alpha
        return NSColor(
            srgbRed: look.tint.red * tintShare,
            green: look.tint.green * tintShare,
            blue: look.tint.blue * tintShare,
            alpha: alpha
        )
    }

    private func roundedMask() -> NSImage {
        let edgeLength = panelCornerRadius * 2 + 1
        let mask = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: panelCornerRadius, yRadius: panelCornerRadius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: panelCornerRadius, left: panelCornerRadius, bottom: panelCornerRadius, right: panelCornerRadius)
        mask.resizingMode = .stretch
        return mask
    }
}

/// A blur with adjustable strength. macOS has no public setting for it, so this sets the radius on the
/// blur filter inside the effect view, and again each time AppKit rebuilds those layers. If a future
/// macOS changes the internals, the guard below finds nothing and the standard blur stays.
@MainActor
final class AdjustableBlurView: NSVisualEffectView {
    var blurRadius = PanelLook.systemBlurRadius {
        didSet { applyBlurRadius() }
    }

    override func updateLayer() {
        super.updateLayer()
        applyBlurRadius()
    }

    override func layout() {
        super.layout()
        applyBlurRadius()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBlurRadius()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyBlurRadius()
    }

    private func applyBlurRadius() {
        guard let layer,
              let backdropLayer = Self.backdropLayer(in: layer),
              let filters = backdropLayer.filters as? [NSObject],
              filters.contains(where: { filter in (filter.value(forKey: "name") as? String) == "gaussianBlur" })
        else { return }
        backdropLayer.setValue(blurRadius, forKeyPath: "filters.gaussianBlur.inputRadius")
    }

    private static func backdropLayer(in layer: CALayer) -> CALayer? {
        if String(describing: type(of: layer)) == "CABackdropLayer" { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let backdropLayer = backdropLayer(in: sublayer) { return backdropLayer }
        }
        return nil
    }
}

/// Draws a small pre-made tile across the panel. It only redraws on resize, so it costs nothing at rest.
@MainActor
final class TextureView: NSView {
    var pattern: TexturePattern = .none {
        didSet {
            guard pattern != oldValue else { return }
            tile = makeTile(for: pattern)
            needsDisplay = true
        }
    }

    private var tile: CGImage?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let tile, let context = NSGraphicsContext.current?.cgContext else { return }
        // Tiles are built at 2x so they stay crisp on Retina screens.
        let tileSize = CGSize(width: CGFloat(tile.width) / 2, height: CGFloat(tile.height) / 2)
        context.draw(tile, in: CGRect(origin: .zero, size: tileSize), byTiling: true)
    }

    private func makeTile(for pattern: TexturePattern) -> CGImage? {
        switch pattern {
        case .none:
            return nil
        case .grain:
            return grainTile()
        case .dots:
            return drawnTile(width: 32, height: 32) { context in
                context.setFillColor(CGColor(gray: 1, alpha: 0.45))
                context.fillEllipse(in: CGRect(x: 14.5, y: 14.5, width: 3, height: 3))
            }
        case .grid:
            return drawnTile(width: 48, height: 48) { context in
                context.setFillColor(CGColor(gray: 1, alpha: 0.13))
                context.fill(CGRect(x: 0, y: 0, width: 48, height: 1))
                context.fill(CGRect(x: 0, y: 0, width: 1, height: 48))
            }
        case .scanlines:
            return drawnTile(width: 8, height: 6) { context in
                context.setFillColor(CGColor(gray: 1, alpha: 0.07))
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 2))
            }
        }
    }

    private func grainTile() -> CGImage? {
        let tileLength = 256
        return drawnTile(width: tileLength, height: tileLength) { context in
            guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return }
            for row in 0..<tileLength {
                for column in 0..<tileLength {
                    let offset = row * context.bytesPerRow + column * 4
                    let alpha = UInt8.random(in: 0...40)
                    let premultipliedValue = Bool.random() ? alpha : 0  // Half white specks, half black
                    pixels[offset] = premultipliedValue
                    pixels[offset + 1] = premultipliedValue
                    pixels[offset + 2] = premultipliedValue
                    pixels[offset + 3] = alpha
                }
            }
        }
    }

    private func drawnTile(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        draw(context)
        return context.makeImage()
    }
}

/// Borderless panels have no frame to grab, so this corner handles resizing. The height follows the list,
/// so only the width changes.
@MainActor
final class ResizeGripView: NSView {
    private var initialFrame = NSRect.zero
    private var initialMouseLocation = NSPoint.zero

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .frameResize(position: .right, directions: .all))
    }

    override func mouseDown(with event: NSEvent) {
        initialFrame = window?.frame ?? .zero
        initialMouseLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let width = initialFrame.width + NSEvent.mouseLocation.x - initialMouseLocation.x
        let clampedWidth = min(max(width, window.minSize.width), window.maxSize.width)
        window.setFrame(NSRect(x: initialFrame.minX, y: window.frame.minY, width: clampedWidth, height: window.frame.height), display: true)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 1, alpha: 0.25).setStroke()
        for inset in [5.0, 9.0] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.maxX - 4, y: inset))
            path.line(to: NSPoint(x: bounds.maxX - inset, y: 4))
            path.lineWidth = 1
            path.stroke()
        }
    }
}
