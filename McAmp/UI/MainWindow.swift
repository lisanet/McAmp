import Cocoa
import Combine
import QuartzCore

private final class WinampAuxiliaryWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

class MainWindow: NSWindow {
    // Keep these public properties unchanged so the rest of the application can
    // continue to bind to the same view instances.
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()

    private let equalizerWindow: WinampAuxiliaryWindow
    private let playlistWindow: WinampAuxiliaryWindow
    private let dockingController = WindowDockingController()
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?

    var showEqualizer: Bool = true {
        didSet {
            mainPlayerView.isEQActive = showEqualizer
            if showEqualizer {
                equalizerWindow.orderFront(nil)
            } else {
                equalizerWindow.orderOut(nil)
            }
        }
    }

    var showPlaylist: Bool = true {
        didSet {
            mainPlayerView.isPLActive = showPlaylist
            if showPlaylist {
                playlistWindow.orderFront(nil)
            } else {
                playlistWindow.orderOut(nil)
            }
        }
    }

    var alwaysOnTop: Bool = false {
        didSet {
            let newLevel: NSWindow.Level = alwaysOnTop ? .floating : .normal
            level = newLevel
            equalizerWindow.level = newLevel
            playlistWindow.level = newLevel
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init() {
        let s = WinampTheme.scale
        let logicalWidth = WinampTheme.windowWidth
        let mainHeight = mainPlayerView.desiredHeight
        let eqHeight = equalizerView.desiredHeight
        let playlistHeight = WinampTheme.playlistMinHeight
        let scaledWidth = (logicalWidth * s).rounded()

        func makeAuxWindow(height: CGFloat) -> WinampAuxiliaryWindow {
            let rect = NSRect(x: 0, y: 0,
                              width: scaledWidth,
                              height: (height * s).rounded())
            let window = WinampAuxiliaryWindow(
                contentRect: rect,
                styleMask: [.borderless, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.isMovableByWindowBackground = false
            window.backgroundColor = WinampTheme.frameBackground
            window.isOpaque = true
            window.hasShadow = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            return window
        }

        equalizerWindow = makeAuxWindow(height: eqHeight)
        playlistWindow = makeAuxWindow(height: playlistHeight)

        // Place the entire initial MAIN -> EQ -> PLAYLIST stack on screen.
        // Starting MAIN at y=100 would put the docked panels off-screen.
        let totalStackHeight = ((mainHeight + eqHeight + playlistHeight) * s).rounded()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let stackTop = screen.maxY - 40
        let initialMainY = min(screen.maxY - (mainHeight * s).rounded(),
                               max(screen.minY + totalStackHeight - (mainHeight * s).rounded(),
                                   stackTop - (mainHeight * s).rounded()))
        let mainRect = NSRect(x: screen.minX + 100, y: initialMainY,
                              width: scaledWidth,
                              height: (mainHeight * s).rounded())
        super.init(
            contentRect: mainRect,
            styleMask: [.borderless, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = false
        level = .normal
        backgroundColor = WinampTheme.frameBackground
        isOpaque = true
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        install(view: mainPlayerView, in: self, logicalHeight: mainHeight)
        install(view: equalizerView, in: equalizerWindow, logicalHeight: eqHeight)
        install(view: playlistView, in: playlistWindow, logicalHeight: playlistHeight)

        dockingController.register(self, as: .main)
        dockingController.register(equalizerWindow, as: .equalizer)
        dockingController.register(playlistWindow, as: .playlist)

        wireDragging()

        // Initial classic Winamp stack: MAIN -> EQ -> PLAYLIST.
        dockingController.dock(.equalizer, to: .main)
        dockingController.dock(.playlist, to: .equalizer)
    }

    func captureDockLayout() -> DockLayoutState {
        dockingController.captureLayout()
    }

    @discardableResult
    func restoreDockLayout(_ layout: DockLayoutState) -> Bool {
        dockingController.restoreLayout(layout)
    }

    private func install(view: NSView, in window: NSWindow, logicalHeight: CGFloat) {
        let s = WinampTheme.scale
        let scaledWidth = (WinampTheme.windowWidth * s).rounded()
        let scaledHeight = (logicalHeight * s).rounded()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
        container.setBoundsSize(NSSize(width: WinampTheme.windowWidth, height: logicalHeight))
        container.wantsLayer = true
        window.contentView = container
        view.frame = container.bounds
        view.autoresizingMask = [.width, .height]
        container.addSubview(view)
    }

    private func wireDragging() {
        mainPlayerView.onTitleBarDragBegan = { [weak self] point in
            self?.dockingController.beginDragging(.main, mouseLocation: point)
        }
        mainPlayerView.onTitleBarDragChanged = { [weak self] point in
            self?.dockingController.updateDragging(mouseLocation: point)
        }
        mainPlayerView.onTitleBarDragEnded = { [weak self] point in
            self?.dockingController.endDragging(mouseLocation: point)
        }

        equalizerView.onTitleBarDragBegan = { [weak self] point in
            self?.dockingController.beginDragging(.equalizer, mouseLocation: point)
        }
        equalizerView.onTitleBarDragChanged = { [weak self] point in
            self?.dockingController.updateDragging(mouseLocation: point)
        }
        equalizerView.onTitleBarDragEnded = { [weak self] point in
            self?.dockingController.endDragging(mouseLocation: point)
        }

        // PlaylistView gets the same three callbacks; see PlaylistView_DockingPatch.swift.
        playlistView.onTitleBarDragBegan = { [weak self] point in
            self?.dockingController.beginDragging(.playlist, mouseLocation: point)
        }
        playlistView.onTitleBarDragChanged = { [weak self] point in
            self?.dockingController.updateDragging(mouseLocation: point)
        }
        playlistView.onTitleBarDragEnded = { [weak self] point in
            self?.dockingController.endDragging(mouseLocation: point)
        }
    }

    /// Kept for source compatibility with existing callers. Window sizes no longer
    /// depend on visibility because EQ and playlist now live in independent windows.
    func recalculateSize() {
        mainPlayerView.needsLayout = true
        equalizerView.needsLayout = true
        playlistView.needsLayout = true
    }

    override func orderFront(_ sender: Any?) {
        super.orderFront(sender)
        if showEqualizer { equalizerWindow.orderFront(sender) }
        if showPlaylist { playlistWindow.orderFront(sender) }
    }

    override func orderOut(_ sender: Any?) {
        equalizerWindow.orderOut(sender)
        playlistWindow.orderOut(sender)
        super.orderOut(sender)
    }

    override func miniaturize(_ sender: Any?) {
        equalizerWindow.orderOut(sender)
        playlistWindow.orderOut(sender)
        super.miniaturize(sender)
    }

    override func deminiaturize(_ sender: Any?) {
        super.deminiaturize(sender)
        if showEqualizer { equalizerWindow.orderFront(sender) }
        if showPlaylist { playlistWindow.orderFront(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            NSApp.sendAction(#selector(AppDelegate.togglePlayPause), to: nil, from: self)
            return
        }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            let seekStep: TimeInterval = 5
            switch event.keyCode {
            case 123:
                if let engine = audioEngine { engine.seek(to: max(0, engine.currentTime - seekStep)) }
                return
            case 124:
                if let engine = audioEngine { engine.seek(to: min(engine.duration, engine.currentTime + seekStep)) }
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager) {
        self.audioEngine = audioEngine
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager, playlistView: playlistView)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager)

        playlistView.onMiniPrev = { [weak playlistManager] in playlistManager?.playPrevious() }
        playlistView.onMiniPlay = { [weak self, weak audioEngine, weak playlistManager] in
            guard let self, let engine = audioEngine else { return }
            if engine.playState == .stopped, let pm = playlistManager {
                pm.playTrack(at: self.playlistView.selectedTrackIndex())
            } else {
                engine.play()
            }
        }
        playlistView.onMiniPause = { [weak audioEngine] in audioEngine?.pause() }
        playlistView.onMiniStop = { [weak audioEngine] in audioEngine?.stop() }
        playlistView.onMiniNext = { [weak self, weak playlistManager] in
            guard let self else { return }
            let selectedTrackIndex = self.playlistView.selectedTrackIndex()
            if selectedTrackIndex != playlistManager?.currentIndex {
                playlistManager?.currentIndex = selectedTrackIndex - 1
            }
            playlistManager?.playNext()
        }

        mainPlayerView.onToggleEQ = { [weak self] in self?.showEqualizer.toggle() }
        mainPlayerView.onTogglePL = { [weak self] in self?.showPlaylist.toggle() }
    }

    func applyRegionMaskFromCurrentSkin() {
        mainPlayerView.wantsLayer = true
        if let region = SkinManager.shared.currentSkin.mainWindowRegion {
            let mask = CAShapeLayer()
            mask.path = region.cgPath
            mask.fillColor = NSColor.black.cgColor
            mask.contentsScale = backingScaleFactor
            mainPlayerView.layer?.mask = mask
            isOpaque = false
            backgroundColor = .clear
        } else {
            mainPlayerView.layer?.mask = nil
            isOpaque = true
            backgroundColor = WinampTheme.frameBackground
        }
        invalidateShadow()
    }
}
