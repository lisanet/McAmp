import Cocoa
import Combine
import QuartzCore

private final class WinampAuxiliaryWindow: NSWindow {
    var onMouseDown: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            onMouseDown?()
        }
        super.sendEvent(event)
    }
}

class MainWindow: NSWindow {
    // Keep these public properties unchanged so the rest of the application can
    // continue to bind to the same view instances.
    let mainPlayerView = MainPlayerView()
    let equalizerView = EqualizerView()
    let playlistView = PlaylistView()
    private let transport = TransportActions()

    private let equalizerWindow: WinampAuxiliaryWindow
    private let playlistWindow: WinampAuxiliaryWindow
    private let dockingController = WindowDockingController()
    private var cancellables = Set<AnyCancellable>()
    private weak var audioEngine: AudioEngine?
    private(set) var playlistLogicalWidth = WinampTheme.windowWidth
    private var playlistLogicalHeight = WinampTheme.playlistMinHeight
    private var playlistEffectiveHeight: CGFloat {
        playlistView.isShaded ? WinampTheme.shadedHeight : playlistLogicalHeight
    }
    private var playlistContainer: NSView?
    private var appliedWindowScale = WinampTheme.scale
    private var mainLogicalHeight: CGFloat {
        mainPlayerView.isShaded ? WinampTheme.shadedHeight : WinampTheme.mainPlayerHeight
    }
    private var eqLogicalHeight: CGFloat {
        equalizerView.isShaded ? WinampTheme.shadedHeight : WinampTheme.equalizerHeight
    }
    
    private func applyPlaylistGeometry(keepingTopLeft: Bool) {
        let scale = WinampTheme.scale
        let height = playlistEffectiveHeight
        let size = NSSize(width: (playlistLogicalWidth * scale).rounded(),
                          height: (height * scale).rounded())
        
        if keepingTopLeft {
                dockingController.resizeKeepingTopLeft(.playlist, to: size)
            } else {
                playlistWindow.setFrame(NSRect(origin: playlistWindow.frame.origin, size: size), display: false)
            }

        if let container = playlistWindow.contentView {
            container.frame = NSRect(origin: .zero, size: size)
            container.setBoundsSize(NSSize(width: playlistLogicalWidth, height: height))
            playlistView.frame = container.bounds
            playlistView.updateLogicalSize(width: playlistLogicalWidth, height: height)
            playlistView.needsLayout = true
            playlistView.needsDisplay = true
        }
    }

    func setPlaylistLogicalSize(width: CGFloat, height: CGFloat) {
        guard width != playlistLogicalWidth || height != playlistLogicalHeight else { return }
        playlistLogicalWidth = width
        playlistLogicalHeight = height
        applyPlaylistGeometry(keepingTopLeft: true)
    }

    private func applyShadeState(id: DockWindowID, window: NSWindow, view: NSView, logicalHeight: CGFloat) {
        let scale = WinampTheme.scale
        let size = NSSize(width: (WinampTheme.windowWidth * scale).rounded(),
                          height: (logicalHeight * scale).rounded())
        dockingController.resizeKeepingTopLeft(id, to: size)

        if let container = window.contentView {
            container.setBoundsSize(NSSize(width: WinampTheme.windowWidth, height: logicalHeight))
            view.frame = container.bounds
        }
        view.needsLayout = true
        view.needsDisplay = true
    }

    private func applyMainShadeState() {
        applyShadeState(id: .main, window: self, view: mainPlayerView, logicalHeight: mainLogicalHeight)
        applyRegionMaskFromCurrentSkin()
    }

    private func applyEqShadeState() {
        applyShadeState(id: .equalizer, window: equalizerWindow, view: equalizerView, logicalHeight: eqLogicalHeight)
    }
    
    private func applyPlaylistShadeState() {
        applyPlaylistGeometry(keepingTopLeft: true)
    }
    
    private func applyAllWindowScales() {
        let previousFrames = dockingController.windowFrames()
        let previousScale = appliedWindowScale
        let scale = WinampTheme.scale
        for (window, view, width, height) in [
            (self as NSWindow, mainPlayerView as NSView, WinampTheme.windowWidth, mainLogicalHeight),
            (equalizerWindow as NSWindow, equalizerView as NSView, WinampTheme.windowWidth, eqLogicalHeight)
        ] {
            let old = window.frame
            let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
            window.setFrame(NSRect(x: old.minX, y: old.maxY - size.height,
                                   width: size.width, height: size.height), display: true)
            if let container = window.contentView {
                container.setBoundsSize(NSSize(width: width, height: height))
                view.frame = container.bounds
                view.needsLayout = true
            }
        }
        applyPlaylistGeometry(keepingTopLeft: true)
        dockingController.repositionAfterScale(from: previousFrames, ratio: scale / previousScale)
        appliedWindowScale = scale
    }

    var showEqualizer: Bool = true {
        didSet {
            mainPlayerView.isEQActive = showEqualizer
            if showEqualizer {
                dockingController.show(.equalizer)
                equalizerWindow.order(.below, relativeTo: windowNumber)
                bringAllWindowsToFront(prioritizing: self)
            } else {
                dockingController.hide(.equalizer)
                equalizerWindow.orderOut(nil)
            }
        }
    }

    var showPlaylist: Bool = true {
        didSet {
            mainPlayerView.isPLActive = showPlaylist
            if showPlaylist {
                dockingController.show(.playlist)
                let anchor = showEqualizer ? equalizerWindow.windowNumber : windowNumber
                playlistWindow.order(.below, relativeTo: anchor)
                bringAllWindowsToFront(prioritizing: self)
            } else {
                dockingController.hide(.playlist)
                playlistWindow.orderOut(nil)
            }
        }
    }
    
    var playlistShadedPlay: Bool = false {
        didSet {
            guard playlistView.isShaded else { return }
            let state = audioEngine?.playState
            if state != .playing {
                transport.play()
            } else {
                transport.pause()
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
        let mainHeight = WinampTheme.mainPlayerHeight
        let eqHeight = WinampTheme.equalizerHeight
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

        dockingController.isHiddenProvider = { [weak self] id in
            guard let self else { return false }
            switch id {
            case .equalizer: return !self.showEqualizer
            case .playlist:  return !self.showPlaylist
            case .main:      return false
            }
        }
        
        isMovableByWindowBackground = false
        level = .normal
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

        mainPlayerView.titleBarButtons.onMenu = { [weak self] in self?.mainPlayerView.showWindowMenu() }
        mainPlayerView.titleBarButtons.onMinimize = { [weak self] in self?.mainPlayerView.window?.miniaturize(nil) }
        
        mainPlayerView.titleBarButtons.onShadeChanged = { [weak self] _ in self?.applyMainShadeState() }
        equalizerView.titleBarButtons.onShadeChanged = { [weak self] _ in self?.applyEqShadeState() }
        playlistView.titleBarButtons.onShadeChanged = { [weak self] _ in self?.applyPlaylistShadeState() }
        
        mainPlayerView.titleBarButtons.onClose = { NSApp.hide(nil) }
        equalizerView.titleBarButtons.onClose = { [weak self] in self?.showEqualizer = false }
        playlistView.titleBarButtons.onClose = { [weak self] in self?.showPlaylist = false}
        
        // Initial classic Winamp stack: MAIN -> EQ -> PLAYLIST.
        dockingController.dock(.equalizer, to: .main)
        dockingController.dock(.playlist, to: .equalizer)
        playlistView.onResizeBegan = { [weak self] in
            guard let self else { return (WinampTheme.windowWidth, WinampTheme.playlistMinHeight, WinampTheme.scale) }
            return (self.playlistLogicalWidth, self.playlistLogicalHeight, WinampTheme.scale)
        }
        playlistView.onResizeChanged = { [weak self] w, h in
            self?.setPlaylistLogicalSize(width: w, height: h)
        }

        setupWindowActivation()
    }

    func captureDockLayout() -> DockLayoutState {
        var layout = dockingController.captureLayout()
        layout.mainShaded = mainPlayerView.isShaded
        layout.eqShaded = equalizerView.isShaded
        layout.playlistShaded = playlistView.isShaded
        layout.playlistLogicalWidth = playlistLogicalWidth
        layout.playlistLogicalHeight = playlistLogicalHeight
        return layout
    }

    @discardableResult
    func restoreDockLayout(_ layout: DockLayoutState) -> Bool {
         if let w = layout.playlistLogicalWidth { playlistLogicalWidth = w }
         if let h = layout.playlistLogicalHeight { playlistLogicalHeight = h }

         mainPlayerView.isShaded = layout.mainShaded
         equalizerView.isShaded = layout.eqShaded
         playlistView.isShaded = layout.playlistShaded

         applyMainShadeState()
         applyEqShadeState()
         applyPlaylistGeometry(keepingTopLeft: true)

        let restored = dockingController.restoreLayout(layout)
        if restored {
            if !showEqualizer { dockingController.hide(.equalizer) }
            if !showPlaylist  { dockingController.hide(.playlist) }
        }
       
        
         return dockingController.restoreLayout(layout)
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
            guard let self else { return }
            self.bringAllWindowsToFront(prioritizing: self)
            self.dockingController.beginDragging(.main, mouseLocation: point)
        }
        mainPlayerView.onTitleBarDragChanged = { [weak self] point in
            self?.dockingController.updateDragging(mouseLocation: point)
        }
        mainPlayerView.onTitleBarDragEnded = { [weak self] point in
            self?.dockingController.endDragging(mouseLocation: point)
        }

        equalizerView.onTitleBarDragBegan = { [weak self] point in
            guard let self else { return }
            self.bringAllWindowsToFront(prioritizing: self.equalizerWindow)
            self.dockingController.beginDragging(.equalizer, mouseLocation: point)
        }
        equalizerView.onTitleBarDragChanged = { [weak self] point in
            self?.dockingController.updateDragging(mouseLocation: point)
        }
        equalizerView.onTitleBarDragEnded = { [weak self] point in
            self?.dockingController.endDragging(mouseLocation: point)
        }

        // PlaylistView gets the same three callbacks; see PlaylistView_DockingPatch.swift.
        playlistView.onTitleBarDragBegan = { [weak self] point in
            guard let self else { return }
            self.bringAllWindowsToFront(prioritizing: self.playlistWindow)
            self.dockingController.beginDragging(.playlist, mouseLocation: point)
        }
        playlistView.onTitleBarDragChanged = { [weak self] point in
            self?.dockingController.updateDragging(mouseLocation: point)
        }
        playlistView.onTitleBarDragEnded = { [weak self] point in
            self?.dockingController.endDragging(mouseLocation: point)
        }
    }

    private func setupWindowActivation() {
        equalizerWindow.onMouseDown = { [weak self] in
            guard let self else { return }
            self.bringAllWindowsToFront(prioritizing: self.equalizerWindow)
        }
        playlistWindow.onMouseDown = { [weak self] in
            guard let self else { return }
            self.bringAllWindowsToFront(prioritizing: self.playlistWindow)
        }

        for win in [self as NSWindow, equalizerWindow, playlistWindow] {
            NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: win)
                .sink { [weak self] notification in
                    guard let self, let activated = notification.object as? NSWindow else { return }
                    self.bringAllWindowsToFront(prioritizing: activated)
                }
                .store(in: &cancellables)
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.bringAllWindowsToFront()
            }
            .store(in: &cancellables)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            bringAllWindowsToFront(prioritizing: self)
        }
        super.sendEvent(event)
    }

    private var isOrderingWindows = false

    func bringAllWindowsToFront(prioritizing topWindow: NSWindow? = nil) {
        guard !isOrderingWindows, isVisible else { return }
        isOrderingWindows = true
        defer { isOrderingWindows = false }

        let top: NSWindow
        if let topWindow, topWindow == self || topWindow == equalizerWindow || topWindow == playlistWindow {
            top = topWindow
        } else if isKeyWindow {
            top = self
        } else if equalizerWindow.isKeyWindow {
            top = equalizerWindow
        } else if playlistWindow.isKeyWindow {
            top = playlistWindow
        } else {
            top = self
        }

        top.orderFront(nil)

        var others: [NSWindow] = []
        if top != self { others.append(self) }
        if showEqualizer && top != equalizerWindow { others.append(equalizerWindow) }
        if showPlaylist && top != playlistWindow { others.append(playlistWindow) }

        var anchor = top.windowNumber
        for window in others {
            window.order(.below, relativeTo: anchor)
            anchor = window.windowNumber
        }
    }

    /// Kept for source compatibility with existing callers. Window sizes no longer
    /// depend on visibility because EQ and playlist now live in independent windows.
    func recalculateSize() {
        applyAllWindowScales()
    }

    override func orderFront(_ sender: Any?) {
        bringAllWindowsToFront(prioritizing: self)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        bringAllWindowsToFront(prioritizing: self)
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
        bringAllWindowsToFront(prioritizing: self)
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
        transport.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager, playlistView: playlistView)
        mainPlayerView.bindToModels(audioEngine: audioEngine, playlistManager: playlistManager, playlistView: playlistView, transport: transport)
        equalizerView.bindToModel(audioEngine: audioEngine, playlistManager: playlistManager)
        playlistView.bindToModel(playlistManager: playlistManager)

        playlistView.miniControls.onPrevious = transport.previous
        playlistView.miniControls.onPlay = transport.play
        playlistView.miniControls.onPause = transport.pause
        playlistView.miniControls.onStop = transport.stop
        playlistView.miniControls.onNext = transport.next
        playlistView.miniControls.onEject = transport.eject
        
        playlistView.titleBarButtons.onMinimize = { [weak self] in
            self?.playlistShadedPlay.toggle()
        }

        mainPlayerView.onToggleEQ = { [weak self] in self?.showEqualizer.toggle() }
        mainPlayerView.onTogglePL = { [weak self] in self?.showPlaylist.toggle() }
    }

    func applyRegionMaskFromCurrentSkin() {
        mainPlayerView.wantsLayer = true
        if !mainPlayerView.isShaded, let region = SkinManager.shared.currentSkin.mainWindowRegion {
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
        }
        invalidateShadow()
    }
}
