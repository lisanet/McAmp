import Cocoa
import Combine
import UniformTypeIdentifiers


class MainPlayerView: NSView {
    // Callbacks
    var onToggleEQ: (() -> Void)?
    var onTogglePL: (() -> Void)?

    var isEQActive: Bool {
        get { eqButton.isActive }
        set { eqButton.isActive = newValue }
    }
    var isPLActive: Bool {
        get { plButton.isActive }
        set { plButton.isActive = newValue }
    }

    // Subviews
    private let titleBar = TitleBarView()
    private let timeDisplay = SevenSegmentView()
    private let spectrumView = SpectrumView()
    private let lcdDisplay = LCDDisplay()
    private let seekSlider = WinampSlider(style: .seek)
    private let volumeSlider = WinampSlider(style: .volume)
    private let balanceSlider = WinampSlider(style: .balance)
    private let transportBar = TransportBar()

    // Toggle buttons
    private let shuffleButton = WinampButton(title: "", style: .toggle)
    private let repeatButton = WinampButton(title: "", style: .toggle)
    private let eqButton = WinampButton(title: "EQ", style: .toggle)
    private let plButton = WinampButton(title: "PL", style: .toggle)

    // Play state indicator
    private let playIndicator = PlayStateIndicator()

    // Invisible click hit-zones for close/minimize/menu when skinned (replace hidden titleBar)
    private let closeHitZone = NSView()
    private let minimizeHitZone = NSView()
    private let menuHitZone = NSView()
    // Click target over the Nullsoft logo baked into main.bmp, right of the repeat button.
    private let githubHitZone = NSView()

    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var audioEngine: AudioEngine?
    private weak var playlistManager: PlaylistManager?
    private weak var playlistView: PlaylistView?
    private var radioClockTimer: Timer?
    private var lastRadioClockMinute: Int?

    // Window dragging state for skinned mode (titleBar is hidden)
    private var dragOrigin: NSPoint?

    /// View height in logical (pre-scale) points. Winamp's main.bmp is exactly
    /// 116 px tall, so when a skin is active we shrink the view to match and
    /// lay out subviews at the sprite's native pixel coordinates.

    let desiredHeight: CGFloat = 116
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // self?.applySkinVisibility()
                self?.needsDisplay = true
                self?.needsLayout = true
            }
        // applySkinVisibility()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        // Title bar
        // titleBar.titleText = "WAMP"
        titleBar.showButtons = true
        titleBar.onClose = { NSApp.terminate(nil) }
        titleBar.onMinimize = { [weak self] in self?.window?.miniaturize(nil) }
        titleBar.onMenuClick = { [weak self] in self?.showWindowMenu() }
        addSubview(titleBar)

        // Time display
        timeDisplay.wantsLayer = true
        addSubview(timeDisplay)
        addSubview(playIndicator)

        // Spectrum
        spectrumView.wantsLayer = true
        addSubview(spectrumView)

        // LCD (track title)
        addSubview(lcdDisplay)

        // Seek slider
        seekSlider.maxValue = 1
        addSubview(seekSlider)

        // Volume
        volumeSlider.value = 0.75
        volumeSlider.maxValue = 1
        addSubview(volumeSlider)

        // Balance
        balanceSlider.value = 0.5
        balanceSlider.minValue = 0
        balanceSlider.maxValue = 1
        addSubview(balanceSlider)

        // Transport bar
        addSubview(transportBar)

        addSubview(shuffleButton)

        addSubview(repeatButton)

        // EQ / PL buttons
        eqButton.isActive = true
        plButton.isActive = true
        addSubview(eqButton)
        addSubview(plButton)

        // Wire skin sprite keys for the four toggle buttons
        shuffleButton.spriteKeyProvider = { active, pressed in .shuffleButton(active: active, pressed: pressed) }
        repeatButton.spriteKeyProvider  = { active, pressed in .repeatButton(active: active, pressed: pressed) }
        eqButton.spriteKeyProvider      = { active, pressed in .eqToggleButton(active: active, pressed: pressed) }
        plButton.spriteKeyProvider      = { active, pressed in .plToggleButton(active: active, pressed: pressed) }

        // Button actions
        shuffleButton.onClick = { [weak self] in
            self?.playlistManager?.shuffleTracks()
        }
        repeatButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            let next = RepeatMode(rawValue: (engine.repeatMode.rawValue + 1) % 3) ?? .off
            engine.repeatMode = next
        }
        eqButton.onClick = { [weak self] in self?.onToggleEQ?() }
        plButton.onClick = { [weak self] in self?.onTogglePL?() }

        // Click hit-zones for close/minimize/menu when skinned (titleBar is hidden
        // then, so we need invisible NSViews at the locations where main.bmp paints
        // these buttons so the user can still interact with them).
        addSubview(closeHitZone)
        addSubview(minimizeHitZone)
        addSubview(menuHitZone)
        addSubview(githubHitZone)
        let closeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedClose))
        closeHitZone.addGestureRecognizer(closeClick)
        let minimizeClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedMinimize))
        minimizeHitZone.addGestureRecognizer(minimizeClick)
        let menuClick = NSClickGestureRecognizer(target: self, action: #selector(handleSkinnedMenu))
        menuHitZone.addGestureRecognizer(menuClick)
        let githubClick = NSClickGestureRecognizer(target: self, action: #selector(handleOpenGitHub))
        githubHitZone.addGestureRecognizer(githubClick)
    }

    @objc private func handleSkinnedClose() { NSApp.terminate(nil) }
    @objc private func handleSkinnedMinimize() { window?.miniaturize(nil) }
    @objc private func handleSkinnedMenu() { showWindowMenu() }
    @objc private func handleOpenGitHub() {
        if let url = URL(string: "https://github.com/lisanet/mcamp") {
            NSWorkspace.shared.open(url)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawSkinned()
    }

    private func drawSkinned() {
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        // View is resized to 116 px (native main.bmp height) when skinned,
        // so the sprite fills bounds exactly and sub-sprite coordinates are
        // in the same space as Webamp's main-window.css.
        let mainHeight: CGFloat = bounds.height
        if let bg = WinampTheme.sprite(.mainBackground) {
            bg.draw(in: bounds)
        }

        // Title bar overlay (main.bmp leaves the top 14px empty for this).
        // Webamp y=0..14 (top-down) → AppKit y = mainHeight - 14.
        let isActive = window?.isKeyWindow ?? true
        if let tb = WinampTheme.sprite(isActive ? .titleBarActive : .titleBarInactive) {
            tb.draw(in: NSRect(x: 0, y: mainHeight - 14, width: bounds.width, height: 14))
        }

        // Mono / stereo sprites at fixed Webamp coordinates.
        // Webamp positions (top-down): mono at (212, 41) 27w, stereo at (239, 41) 29w, 12 px tall.
        // Convert to AppKit (bottom-up): y_appkit = mainHeight - 41 - 12
        let isStereo = playlistManager?.currentTrack?.isStereo ?? false
        let monoY: CGFloat = mainHeight - 41 - 12
        if let monoSprite = WinampTheme.sprite(.mono(active: !isStereo)) {
            monoSprite.draw(in: NSRect(x: 212, y: monoY, width: 27, height: 12))
        }
        if let stereoSprite = WinampTheme.sprite(.stereo(active: isStereo)) {
            stereoSprite.draw(in: NSRect(x: 239, y: monoY, width: 29, height: 12))
        }

        // Bitrate / sample rate digits via text.bmp.
        // The "kbps" and "khz" *labels* are baked into main.bmp, so only draw the numbers.
        // Webamp positions (top-down): bitrate at (111, 43), sample rate at (156, 43).
        // y_appkit = mainHeight - 43 - 6 (glyphs are 6 px tall) = 67
        if let textSheet = WinampTheme.provider.textSheet,
           let track = playlistManager?.currentTrack {
            let textY: CGFloat = mainHeight - 43 - 6
            var bitrate: Int
            var sampleRate: Int
            if let engine = audioEngine, engine.isRadioStream {
                bitrate = engine.radioBitrate
                sampleRate = engine.radioSampleRate
            } else {
                bitrate = track.bitrate
                sampleRate = track.sampleRate
            }
            let bitrateStr = bitrate > 0 ? String(format: "%3d", bitrate) : "   "
            let sampleStr = sampleRate > 0 ? String(format: "%2d", sampleRate / 1000) : "  "
 
            TextSpriteRenderer.draw(bitrateStr, at: NSPoint(x: 111, y: textY), sheet: textSheet)
            TextSpriteRenderer.draw(sampleStr,  at: NSPoint(x: 156, y: textY), sheet: textSheet)
        }
    }

    override func layout() {
        super.layout()
        layoutSkinned()
        audioEngine?.maxSpectrumBars = 19
    }

    /// Exact Winamp 2.x pixel coordinates, ported from Webamp's main-window.css.
    /// View bounds are 275×116 in this mode; Y is converted from Webamp (top-down)
    /// to AppKit (bottom-up) as: y_appkit = 116 - y_webamp - height.
    private func layoutSkinned() {
        let h: CGFloat = bounds.height  // 116

        // FIXME: implement play state sprites
        playIndicator.isHidden = true
        
        titleBar.isHidden = true
        titleBar.showMenuIcon = false
        // Title bar (hidden, but keep frame valid)
        titleBar.frame = NSRect(x: 0, y: h - 16, width: bounds.width, height: 16)

        // Close / minimize hit-zones — webamp close(264,3,9×9), min(244,3,9×9)
        let hitSize: CGFloat = 11
        let hitY = h - 3 - hitSize
        closeHitZone.frame = NSRect(x: 263, y: hitY, width: hitSize, height: hitSize)
        minimizeHitZone.frame = NSRect(x: 243, y: hitY, width: hitSize, height: hitSize)

        // Menu icon hit-zone — webamp top-left icon at (6, 3, 9×9)
        menuHitZone.frame = NSRect(x: 6, y: hitY, width: hitSize, height: hitSize)

        // 7-segment time (webamp #time at 39,26,59,13 → y=77; widened 1px to fit last digit)
        timeDisplay.frame = NSRect(x: 39, y: 77, width: 60, height: 13)
        // Spectrum / visualizer (webamp 24,43,76,16 → y=57)
        spectrumView.frame = NSRect(x: 24, y: 57, width: 76, height: 16)
        // Scrolling track-title marquee (webamp 111,27,154,6 → y=83)
        lcdDisplay.frame = NSRect(x: 111, y: 83, width: 154, height: 6)

        // Seek/posbar (webamp 16,72,248,10 → y=34)
        seekSlider.frame = NSRect(x: 16, y: 34, width: 248, height: 10)

        // Volume / balance (webamp 107/177,57,68/38,13 → y=46)
        volumeSlider.frame = NSRect(x: 107, y: 46, width: 68, height: 13)
        balanceSlider.frame = NSRect(x: 177, y: 46, width: 38, height: 13)

        // EQ / PL toggle buttons (webamp 219/242,58,23,12 → y=46)
        eqButton.frame = NSRect(x: 219, y: 46, width: 23, height: 12)
        plButton.frame = NSRect(x: 242, y: 46, width: 23, height: 12)

        // Transport (cbuttons, webamp 16,88,*,18 → y=10). Width = sum of 5 buttons + eject.
        transportBar.frame = NSRect(x: 16, y: 10, width: transportBar.intrinsicContentSize.width, height: 18)

        // Shuffle / repeat (webamp 164,89,47,15 and 210,89,28,15 → y=12)
        shuffleButton.frame = NSRect(x: 164, y: 12, width: 47, height: 15)
        repeatButton.frame = NSRect(x: 210, y: 12, width: 28, height: 15)

        // Nullsoft logo (baked into main.bmp at ~249,89,18,15) — repurposed as a link to the repo.
        githubHitZone.frame = NSRect(x: 249, y: 12, width: 18, height: 15)
    }

    // MARK: - Binding
    func bindToModels(audioEngine: AudioEngine, playlistManager: PlaylistManager, playlistView: PlaylistView) {
        self.audioEngine = audioEngine
        self.playlistManager = playlistManager
        self.playlistView = playlistView

        // Time
        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard self?.audioEngine?.isRadioStream != true else { return }
                self?.timeDisplay.timeInSeconds = time }
            .store(in: &cancellables)

        // Spectrum
        audioEngine.$spectrumData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.spectrumView.spectrumData = data }
            .store(in: &cancellables)

        // Track info
        playlistManager.$currentIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTrackInfo()
                // Skinned overlay reads track.bitrate / .sampleRate in drawSkinned —
                // force a redraw so kbps/khz update on track change.
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        // Radio stream title info
        Publishers.CombineLatest3(audioEngine.$isRadioStream, audioEngine.$stationTitle, audioEngine.$streamTitle)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRadioStream, _, _ in
                if isRadioStream {
                    self?.startRadioClock()
                } else {
                    self?.stopRadioClock()
                }
                self?.updateTrackInfo()
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        audioEngine.$radioBitrate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTrackInfo()
                self?.needsDisplay = true
            }
            .store(in: &cancellables)

        audioEngine.$radioSampleRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTrackInfo()
                self?.needsDisplay = true
            }
            .store(in: &cancellables)
        
        // Seek slider
        audioEngine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dur in self?.seekSlider.maxValue = Float(dur) }
            .store(in: &cancellables)

        audioEngine.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self, self.seekSlider.window != nil else { return }
                guard !self.seekSlider.isUserInteracting else { return }
                self.seekSlider.value = Float(time)
            }
            .store(in: &cancellables)

        seekSlider.onChange = { [weak audioEngine] value in
            audioEngine?.seek(to: TimeInterval(value))
        }

        // Volume
        volumeSlider.value = audioEngine.volume
        volumeSlider.onChange = { [weak self, weak audioEngine] value in
            audioEngine?.volume = value
            self?.lcdDisplay.showOverlay("Volume: \(Int(round(value * 100)))%")
        }

        // Balance
        balanceSlider.value = (audioEngine.balance + 1) / 2 // convert -1..1 to 0..1
        balanceSlider.onChange = { [weak audioEngine] value in
            audioEngine?.balance = value * 2 - 1 // convert 0..1 to -1..1
        }

        // Transport
        transportBar.onPrevious = { [weak playlistManager] in playlistManager?.playPrevious() }
        transportBar.onPlay = { [weak self] in
            guard let self, let engine = self.audioEngine else { return }
            if engine.playState == .stopped,
               let pm = self.playlistManager {
                // playTrack honors CUE segment bounds (a bare loadAndPlay(url:)
                // would play the whole album file) and re-arms gapless chaining.
                pm.playTrack(at: playlistView.selectedTrackIndex())
            } else {
                engine.play()
            }
        }
        transportBar.onPause = { [weak audioEngine] in audioEngine?.pause() }
        transportBar.onStop = { [weak audioEngine] in audioEngine?.stop() }
        transportBar.onNext = { [weak playlistManager] in
            let selectedTrackIndex = playlistView.selectedTrackIndex()
            if selectedTrackIndex != playlistManager?.currentIndex {
                playlistManager?.currentIndex = selectedTrackIndex - 1
            }
            playlistManager?.playNext()
        }
        transportBar.onEject = { [weak self] in self?.playlistManager?.openFileFolderList() }

        // Play state
        audioEngine.$isPlaying
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in
                self?.transportBar.playButton.isActive = playing
            }
            .store(in: &cancellables)

        audioEngine.$playState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.playIndicator.state = state
            }
            .store(in: &cancellables)

        // Repeat state
        audioEngine.$repeatMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.repeatButton.isActive = mode != .off
                self?.repeatButton.needsDisplay = true
            }
            .store(in: &cancellables)
    }

    private func updateTrackInfo() {
        guard let track = playlistManager?.currentTrack else {
            return
        }

        if (audioEngine?.isRadioStream == true) || track.isStream {
            let streamDisplay: String
            if let engine = audioEngine, engine.isRadioStream {
                streamDisplay = !engine.radioDisplayTitle.isEmpty ? engine.radioDisplayTitle : track.title
            } else {
                streamDisplay = track.displayTitle
            }
            let newText = "\(streamDisplay)"
            if lcdDisplay.text != newText {
                lcdDisplay.text = newText
            }
        } else {
            let newText = "\(track.displayTitle) (\(track.formattedDuration))"
            if lcdDisplay.text != newText {
                lcdDisplay.text = newText
            }
        }
    }

    private func showWindowMenu() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        let menu = delegate.buildCornerPopupMenu()
        let anchor = NSPoint(x: titleBar.frame.minX, y: titleBar.frame.minY)
        menu.popUp(positioning: nil, at: anchor, in: self)
    }


    // MARK: - Radio Clock

    private func startRadioClock() {
        stopRadioClock()
        updateRadioClock()
        
        radioClockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
                self?.updateRadioClock()
            }
    }

    private func stopRadioClock() {
        radioClockTimer?.invalidate()
        radioClockTimer = nil
    }

    private func updateRadioClock() {
        guard audioEngine?.isRadioStream == true else { return }

        let components = Calendar.current.dateComponents([.hour, .minute],from: Date())
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        guard minute != lastRadioClockMinute else { return }
        
        lastRadioClockMinute = minute
        timeDisplay.timeInSeconds = TimeInterval(hour * 60 + minute)
    }

    // MARK: - Window dragging (skinned mode)
    // When skinned, TitleBarView is hidden so we handle dragging from the title
    // bar area (top 14px of the 116px skin) directly in MainPlayerView.

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let titleBarMinY = bounds.height - 14
        guard point.y >= titleBarMinY else { super.mouseDown(with: event); return }
        // Don't drag from close/minimize/menu hit-zones
        if closeHitZone.frame.contains(point) || minimizeHitZone.frame.contains(point)
            || menuHitZone.frame.contains(point) {
            super.mouseDown(with: event)
            return
        }
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin, let win = window else { return }
        let current = event.locationInWindow
        var frame = win.frame
        frame.origin.x += current.x - origin.x
        frame.origin.y += current.y - origin.y
        win.setFrameOrigin(frame.origin)
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
        super.mouseUp(with: event)
    }
}
