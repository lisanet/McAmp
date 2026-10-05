import Cocoa

class TransportBar: NSView {
    var onPrevious: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onNext: (() -> Void)?
    var onEject: (() -> Void)?

    private(set) var prevButton: WinampButton!
    private(set) var playButton: WinampButton!
    private(set) var pauseButton: WinampButton!
    private(set) var stopButton: WinampButton!
    private(set) var nextButton: WinampButton!
    private(set) var ejectButton: WinampButton!

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupButtons() {
        let buttons = makeButtons()
        prevButton = buttons[0]
        playButton = buttons[1]
        pauseButton = buttons[2]
        stopButton = buttons[3]
        nextButton = buttons[4]
        ejectButton = buttons[5]

        // [weak self]: the bar retains the buttons; a strong capture here is
        // a retain cycle that keeps the whole bar alive forever.
        prevButton.onClick = { [weak self] in self?.onPrevious?() }
        playButton.onClick = { [weak self] in self?.onPlay?() }
        pauseButton.onClick = { [weak self] in self?.onPause?() }
        stopButton.onClick = { [weak self] in self?.onStop?() }
        nextButton.onClick = { [weak self] in self?.onNext?() }
        ejectButton.onClick = { [weak self] in self?.onEject?() }

        // Wire sprite keys for skin rendering
        prevButton.spriteKeyProvider   = { _, pressed in .previous(pressed: pressed) }
        playButton.spriteKeyProvider   = { _, pressed in .play(pressed: pressed) }
        pauseButton.spriteKeyProvider  = { _, pressed in .pause(pressed: pressed) }
        stopButton.spriteKeyProvider   = { _, pressed in .stop(pressed: pressed) }
        nextButton.spriteKeyProvider   = { _, pressed in .next(pressed: pressed) }
        ejectButton.spriteKeyProvider  = { _, pressed in .eject(pressed: pressed) }

        for btn in buttons {
            btn.style = .transport
            addSubview(btn)
        }
    }

    private func makeButtons() -> [WinampButton] {
        (0..<6).map { _ in WinampButton(title: "", style: .transport) }
    }

    override func layout() {
        super.layout()
        let btnW: CGFloat = 22
        let btnH: CGFloat = 18
        let gap: CGFloat = 1
        let buttons = [prevButton!, playButton!, pauseButton!, stopButton!, nextButton!]
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: CGFloat(i) * (btnW + gap), y: 0, width: btnW, height: btnH)
        }
        // eject button has y: 1 and gap: 6, so x = 5 * 22 + 4 + 6 = 120
        ejectButton!.frame = NSRect(x: 120, y: 1, width: 22, height: 16)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 6 * 22 + 4 + 6, height: 18)
    }
}
