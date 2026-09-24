import Cocoa
import Combine

class SpectrumView: NSView {
    var spectrumData: [Float] = [] {
        didSet {
            updatePeaks()
            needsDisplay = true
        }
    }
    var barCount: Int = 0

    /// Winamp convention: 16 vertical rows, each painted with viscolors[2..17] bottom→top.
    private static let rowCount = 16

    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 1
    /// Per-bar peak position (0...rowCount), decays 0.35 rows per spectrumData update.
    private var peaks: [CGFloat] = []
    private var amplitudeBars: [Int] = []

    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updatePeaks() {
        barCount = spectrumData.count // unskinned = 26, skinned = 19
        if amplitudeBars.count != barCount {
            amplitudeBars = Array(repeating: 0, count: barCount)
            peaks = Array(repeating: 0, count: barCount)
        }
        let rows = CGFloat(Self.rowCount)
        for i in 0..<barCount {
            let amplitude = spectrumData[i]
            let barRows = CGFloat(amplitude) * rows
            amplitudeBars[i] = Int(barRows)
            if barRows >= peaks[i] {
                peaks[i] = barRows
            } else {
                peaks[i] = max(0, peaks[i] - 0.35) // falloff rate
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard amplitudeBars.count > 0 else { return }
        let rows = Self.rowCount
        let rowHeight = bounds.height / CGFloat(rows)

        let viscolors = WinampTheme.provider.viscolors
        guard viscolors.count >= 24 else { return }

        // Row colors: viscolors[2..17], skin colors are top -> bottom
        // Peak cap: viscolors[23] per Winamp convention.
        let peakColor = viscolors[23]

        for i in 0..<barCount {
            let litRows = amplitudeBars[i]
            let x = CGFloat(i) * (barWidth + gap)

            // Discrete 16-step bar
            for r in 0..<litRows {
                viscolors[17 - r].setFill()
                NSRect(x: x,
                       y: CGFloat(r) * rowHeight,
                       width: barWidth,
                       height: rowHeight).fill()
            }

            // Peak cap
                let peakRow = Int(peaks[i])
                if peakRow > litRows && peakRow < rows {
                    peakColor.setFill()
                    NSRect(x: x,
                           y: CGFloat(peakRow) * rowHeight,
                           width: barWidth,
                           height: rowHeight).fill()
                }
        }
    }
}
