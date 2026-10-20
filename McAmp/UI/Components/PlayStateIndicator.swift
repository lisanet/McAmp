import Cocoa
import Combine

class PlayStateIndicator: NSView {
    var state: PlayState = .stopped {
        didSet { needsDisplay = true }
    }

    private var skinObserver: AnyCancellable?
 
    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        var stateImg: NSImage?
        switch state {
        case .playing:
            stateImg = WinampTheme.sprite(.playImg)
        case .paused:
            stateImg = WinampTheme.sprite(.pauseImg)
        case .stopped:
            stateImg = WinampTheme.sprite(.emptyImg)
        }
        stateImg?.draw(in: NSRect(x: 0, y: 0, width: 9, height: 9))
    }
}
