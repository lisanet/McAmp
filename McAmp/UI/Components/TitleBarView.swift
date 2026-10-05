import Cocoa
import Combine

class TitleBarView: NSView {
    var titleText: String = "McAmp" { didSet { needsDisplay = true } }
    var showButtons: Bool = true
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onMenuClick: (() -> Void)?
    var showMenuIcon: Bool = false { didSet { needsDisplay = true } }

    private let menuIconSize: CGFloat = 9
    private var menuIconRect: NSRect {
        NSRect(x: 3, y: (bounds.height - menuIconSize) / 2, width: menuIconSize, height: menuIconSize)
    }

    private var skinObserver: AnyCancellable?

    override init(frame: NSRect) {
        super.init(frame: frame)
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSkinned()
    }

    private func drawSkinned() {
        let isActive = window?.isKeyWindow ?? true
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        if let bg = WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive) {
            bg.draw(in: bounds)
        }
        // Title text is baked into the sprite — do not draw the titleText overlay.
        if showButtons {
            let btnSize: CGFloat = 9
            let btnY = (bounds.height - btnSize) / 2
            if let close = WinampTheme.sprite(.titleBarCloseButton(pressed: false)) {
                close.draw(in: NSRect(x: bounds.width - 11, y: btnY, width: btnSize, height: btnSize))
            }
        }
    }

    // MARK: - Window dragging
    private var dragOrigin: NSPoint?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let b = bounds
        let btnSize: CGFloat = 9
        let btnY = (b.height - btnSize) / 2
        let minimizeRect = NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize)
        let closeRect = NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize)

        if showMenuIcon && menuIconRect.contains(point) {
            onMenuClick?()
            return
        }
        if showButtons && (closeRect.contains(point) || minimizeRect.contains(point)) {
            super.mouseDown(with: event)
            return
        }
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else { return }
        let current = event.locationInWindow
        let dx = current.x - origin.x
        let dy = current.y - origin.y
        var frame = win.frame
        frame.origin.x += dx
        frame.origin.y += dy
        win.setFrameOrigin(frame.origin)
    }

    // MARK: - Click handling for window buttons
    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        guard showButtons else { return }
        let point = convert(event.locationInWindow, from: nil)
        let b = bounds
        let btnSize: CGFloat = 9
        let btnY = (b.height - btnSize) / 2

        let minimizeRect = NSRect(x: b.width - 22, y: btnY, width: btnSize, height: btnSize)
        let closeRect = NSRect(x: b.width - 11, y: btnY, width: btnSize, height: btnSize)

        if closeRect.contains(point) {
            onClose?()
        } else if minimizeRect.contains(point) {
            onMinimize?()
        }
    }
}
