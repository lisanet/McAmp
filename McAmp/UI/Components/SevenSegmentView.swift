import Cocoa
import Combine

class SevenSegmentView: NSView {
    var timeInSeconds: TimeInterval = 0 { didSet { needsDisplay = true } }
    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    // Segment layout: 7 segments per digit (a-g), standard arrangement
    // a=top, b=topRight, c=bottomRight, d=bottom, e=bottomLeft, f=topLeft, g=middle
    private let digitSegments: [[Bool]] = [
        [true,  true,  true,  true,  true,  true,  false], // 0
        [false, true,  true,  false, false, false, false], // 1
        [true,  true,  false, true,  true,  false, true],  // 2
        [true,  true,  true,  true,  false, false, true],  // 3
        [false, true,  true,  false, false, true,  true],  // 4
        [true,  false, true,  true,  false, true,  true],  // 5
        [true,  false, true,  true,  true,  true,  true],  // 6
        [true,  true,  true,  false, false, false, false], // 7
        [true,  true,  true,  true,  true,  true,  true],  // 8
        [true,  true,  true,  true,  false, true,  true],  // 9
    ]

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let totalSeconds = Int(max(0, timeInSeconds))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        drawSkinned(minutes: minutes, seconds: seconds)
    }

    /// Skinned path: always MM:SS, native 9×13 digit sprites at the exact
    /// Webamp positions inside the #time container. The colon is baked into
    /// main.bmp at the gap between the minute and second digits.
    private func drawSkinned(minutes: Int, seconds: Int) {
        let mm = min(99, minutes)
        let digits = [mm / 10, mm % 10, seconds / 10, seconds % 10]
        // Local x offsets inside a 59-wide #time container (Webamp CSS).
        let xs: [CGFloat] = [9, 21, 39, 51]
        let size = NSSize(width: 9, height: 13)
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }
        for (i, d) in digits.enumerated() {
            guard let sprite = WinampTheme.sprite(.digit(d)) else { continue }
            sprite.draw(in: NSRect(x: xs[i], y: 0, width: size.width, height: size.height))
        }
    }
}
