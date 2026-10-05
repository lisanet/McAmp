import Cocoa
import Combine

enum WinampSliderStyle {
    case seek       // olive-green, horizontal
    case volume     // orange gradient, horizontal
    case balance    // olive-green, horizontal
    case eqBand     // vertical, yellow-tinted background
}

class WinampSlider: NSView {
    var value: Float = 0 {
        didSet {
            needsDisplay = true
            if isUserInteracting { onChange?(value) }
        }
    }
    var minValue: Float = 0
    var maxValue: Float = 1
    var onChange: ((Float) -> Void)?
    var style: WinampSliderStyle = .seek
    var isVertical: Bool = false

    private var isDragging = false
    private(set) var isUserInteracting = false
    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    convenience init(style: WinampSliderStyle, isVertical: Bool = false) {
        self.init(frame: .zero)
        self.style = style
        self.isVertical = isVertical
        if style == .eqBand {
            self.isVertical = true
            self.minValue = -12
            self.maxValue = 12
        }
    }

    private var normalizedValue: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat((value - minValue) / (maxValue - minValue))
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSkinned()
    }

    private func drawSkinned() {
        let n = normalizedValue
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        switch style {
        case .seek:
            if let bg = WinampTheme.sprite(.seekBackground) {
                bg.draw(in: bounds)
            }
            let thumbW: CGFloat = 29
            let thumbX = n * (bounds.width - thumbW)
            if let thumb = WinampTheme.sprite(.seekThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 10) / 2, width: thumbW, height: 10))
            }

        case .volume:
            let position = Int((n * 27).rounded())
            if let bg = WinampTheme.sprite(.volumeBackground(position: position)) {
                bg.draw(in: bounds)
            }
            let thumbW: CGFloat = 14
            let thumbX = n * (bounds.width - thumbW)
            if let thumb = WinampTheme.sprite(.volumeThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: thumbW, height: 11))
            }

        case .balance:
            let position = Int((n * 27).rounded())
            if let bg = WinampTheme.sprite(.balanceBackground(position: position)) {
                bg.draw(in: bounds)
            }
            let thumbW: CGFloat = 14
            let thumbX = n * (bounds.width - thumbW)
            if let thumb = WinampTheme.sprite(.balanceThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: thumbX, y: (bounds.height - 11) / 2, width: thumbW, height: 11))
            }

        case .eqBand:
            // Winamp bakes the green→red gradient directly into 28 background variants
            // 28 skin slider backbrounds. index 0-13 = -12db - 0dB  index 14-27 = 0dB - 12dB
            let bgPos = Int((n * 27).rounded())
            if let bg = WinampTheme.sprite(.eqSliderBackground(position: bgPos)) {
                bg.draw(in: bounds)
            }
            let thumbY = n * (bounds.height - 11)
            if let thumb = WinampTheme.sprite(.eqSliderThumb(pressed: isUserInteracting)) {
                thumb.draw(in: NSRect(x: 1, y: thumbY, width: 11, height: 11))
            }
        }
    }

    // MARK: - Mouse Handling
    override func mouseDown(with event: NSEvent) {
        // Reset-to-center only makes sense where the midpoint is neutral
        // (balance 0, EQ band 0 dB). On seek/volume a double-click would yank
        // playback to 50% / volume to half instead of honoring the click.
        if event.clickCount == 2, style == .balance || style == .eqBand {
            resetToCenter()
            return
        }
        isDragging = true
        isUserInteracting = true
        updateValueFromMouse(event)
    }

    private func resetToCenter() {
        isUserInteracting = true
        value = (minValue + maxValue) / 2
        isUserInteracting = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        updateValueFromMouse(event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isUserInteracting = false
    }

    private func updateValueFromMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let normalized: CGFloat

        if isVertical {
            normalized = max(0, min(1, point.y / bounds.height))
        } else {
            normalized = max(0, min(1, point.x / bounds.width))
        }

        value = minValue + Float(normalized) * (maxValue - minValue)
    }
}
