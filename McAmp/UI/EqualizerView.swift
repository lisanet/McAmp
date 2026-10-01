import Cocoa
import Combine

struct EQPreset {
    let name: String
    let bands: [Float]

    nonisolated static let presets: [EQPreset] = [
        EQPreset(name: "Acoustic",         bands: [ 5.00,  4.90,  3.95,  1.05,  2.15,  1.75,  3.50,  4.10,  3.55,  2.15]),
        EQPreset(name: "Classical",        bands: [ 4.75,  3.75,  3.00,  2.50, -1.50, -1.50,  0.00,  2.25,  3.25,  3.75]),
        EQPreset(name: "Dance",            bands: [ 3.57,  6.55,  4.99,  0.00,  1.92,  3.65,  5.15,  4.54,  3.59,  0.00]),
        EQPreset(name: "Deep",             bands: [ 4.95,  3.55,  1.75,  1.00,  2.85,  2.50,  1.45, -2.15, -3.55, -4.60]),
        EQPreset(name: "Electronic",       bands: [ 4.25,  3.80,  1.20,  0.00, -2.15,  2.25,  0.85,  1.25,  3.95,  4.80]),
        EQPreset(name: "Flat",             bands: [ 0.00,  0.00,  0.00,  0.00,  0.00,  0.00,  0.00,  0.00,  0.00,  0.00]),
        EQPreset(name: "Hip-Hop",          bands: [ 5.00,  4.25,  1.50,  3.00, -1.00, -1.00,  1.50, -0.50,  2.00,  3.00]),
        EQPreset(name: "Increase Bass",    bands: [ 5.50,  4.25,  3.50,  2.50,  1.25,  0.00,  0.00,  0.00,  0.00,  0.00]),
        EQPreset(name: "Increase Treble",  bands: [ 0.00,  0.00,  0.00,  0.00,  0.00,  1.25,  2.50,  3.50,  4.25,  5.50]),
        EQPreset(name: "Increase Vocals",  bands: [-1.50, -3.00, -3.00,  1.50,  3.75,  3.75,  3.00,  1.50,  0.00, -1.50]),
        EQPreset(name: "Jazz",             bands: [ 4.00,  3.00,  1.50,  2.25, -1.50, -1.50,  0.00,  1.50,  3.00,  3.75]),
        EQPreset(name: "Latin",            bands: [ 4.50,  3.00,  0.00,  0.00, -1.50, -1.50, -1.50,  0.00,  3.00,  4.50]),
        EQPreset(name: "Loudness",         bands: [ 6.00,  4.00,  0.00,  0.00, -2.00,  0.00, -1.00, -5.00,  5.00,  1.00]),
        EQPreset(name: "Lounge",           bands: [-3.00, -1.50, -0.50,  1.50,  4.00,  2.50,  0.00, -1.50,  2.00,  1.00]),
        EQPreset(name: "Piano",            bands: [ 3.00,  2.00,  0.00,  2.50,  3.00,  1.50,  3.50,  4.50,  3.00,  3.50]),
        EQPreset(name: "Pop",              bands: [-1.50, -1.00,  0.00,  2.00,  4.00,  4.00,  2.00,  0.00, -1.00, -1.50]),
        EQPreset(name: "R&B",              bands: [ 2.62,  6.92,  5.65,  1.33, -2.19, -1.50,  2.32,  2.65,  3.00,  3.75]),
        EQPreset(name: "Reduce Bass",      bands: [-5.50, -4.25, -3.50, -2.50, -1.25,  0.00,  0.00,  0.00,  0.00,  0.00]),
        EQPreset(name: "Reduce Treble",    bands: [ 0.00,  0.00,  0.00,  0.00,  0.00, -1.25, -2.50, -3.50, -4.25, -5.50]),
        EQPreset(name: "Rock",             bands: [ 5.00,  4.00,  3.00,  1.50, -0.50, -1.00,  0.50,  2.50,  3.50,  4.50]),
        EQPreset(name: "Small Speakers",   bands: [ 5.50,  4.25,  3.50,  2.50,  1.25,  0.00, -1.25, -2.50, -3.50, -4.25]),
        EQPreset(name: "Spoken Word",      bands: [-3.46, -0.47,  0.00,  0.69,  3.46,  4.61,  4.84,  4.28,  2.54,  0.00]),
    ]
}

class EqualizerView: NSView {
    private let titleBar = TitleBarView()
    private let onButton = WinampButton(title: "ON", style: .toggle)
    private let autoButton = WinampButton(title: "AUTO", style: .toggle)
    private let presetsButton = WinampButton(title: "PRESETS", style: .action)
    private let preampSlider = WinampSlider(style: .eqBand, isVertical: true)
    private let responseView = EQResponseView()
    private var bandSliders: [WinampSlider] = []
    private var bandLabels: [NSTextField] = []
    private var dbLabels: [NSTextField] = []
    private var preLabel: NSTextField?
    private var dbUnitLabel: NSTextField?
    private var cancellables = Set<AnyCancellable>()
    private var skinObserver: AnyCancellable?
    private weak var audioEngine: AudioEngine?
    private var dragOrigin: NSPoint?

    var autoMode: Bool {
        get { autoButton.isActive }
        set { autoButton.isActive = newValue }
    }

    private let bandNames = ["32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

    /// View height in logical points. eqmain.bmp is 116 px tall, so when a skin
    /// is active we shrink the view to match and draw the sprite 1:1. Without a
    /// skin we use Wamp's original 112 px layout.
    var desiredHeight: CGFloat {
        WinampTheme.skinIsActive ? 116 : WinampTheme.equalizerHeight
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = WinampTheme.frameBackground.cgColor
        setupSubviews()
        skinObserver = SkinManager.shared.$currentSkin
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applySkinVisibility()
                self?.needsDisplay = true
                self?.needsLayout = true
            }
        applySkinVisibility()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupSubviews() {
        titleBar.titleText = "WAMP EQUALIZER"
        titleBar.showButtons = false
        addSubview(titleBar)

        onButton.isActive = true
        onButton.onClick = { [weak self] in
            guard let engine = self?.audioEngine else { return }
            engine.eqEnabled.toggle()
            self?.onButton.isActive = engine.eqEnabled
        }
        addSubview(onButton)

        autoButton.isActive = false
        autoButton.onClick = { [weak self] in
            self?.autoButton.isActive.toggle()
        }
        addSubview(autoButton)

        presetsButton.onClick = { [weak self] in self?.showPresetsMenu() }
        addSubview(presetsButton)

        // Preamp
        preampSlider.value = 0
        preampSlider.onChange = { [weak self] value in
            self?.audioEngine?.setPreamp(gain: value)
        }
        addSubview(preampSlider)

        // Response curve
        addSubview(responseView)

        // 10 band sliders
        for i in 0..<10 {
            let slider = WinampSlider(style: .eqBand, isVertical: true)
            slider.value = 0
            let bandIndex = i
            slider.onChange = { [weak self] value in
                self?.audioEngine?.setEQ(band: bandIndex, gain: value)
                self?.responseView.bands = self?.audioEngine?.eqBands ?? []
            }
            bandSliders.append(slider)
            addSubview(slider)

            let label = NSTextField(labelWithString: bandNames[i])
            label.font = WinampTheme.eqLabelFont
            label.textColor = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.75, alpha: 1.0)
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .center
            bandLabels.append(label)
            addSubview(label)
        }

        // dB labels
        for (text, tag) in [("+12 db", 200), ("0 db", 201), ("-12 db", 202)] {
            let label = NSTextField(labelWithString: text)
            label.font = WinampTheme.eqLabelFont
            label.textColor = WinampTheme.preampLabelOrange
            label.isBezeled = false
            label.drawsBackground = false
            label.alignment = .right
            label.tag = tag
            addSubview(label)
            dbLabels.append(label)
        }

        // Preamp label
        let pre = NSTextField(labelWithString: "PREAMP")
        pre.font = WinampTheme.eqLabelFont
        pre.textColor = WinampTheme.eqBandLabelColor
        pre.isBezeled = false
        pre.drawsBackground = false
        pre.alignment = .center
        pre.tag = 210
        addSubview(pre)
        preLabel = pre

        // dB label under response
        let dbU = NSTextField(labelWithString: "dB")
        dbU.font = WinampTheme.eqLabelFont
        dbU.textColor = WinampTheme.eqBandLabelColor
        dbU.isBezeled = false
        dbU.drawsBackground = false
        dbU.alignment = .center
        dbU.tag = 211
        addSubview(dbU)
        dbUnitLabel = dbU

        // Wire EQ button sprite providers (sprites from eqmain.bmp)
        onButton.spriteKeyProvider = { active, pressed in .eqOnButton(active: active, pressed: pressed) }
        autoButton.spriteKeyProvider = { active, pressed in .eqAutoButton(active: active, pressed: pressed) }
        presetsButton.spriteKeyProvider = { _, pressed in .eqPresetsButton(pressed: pressed) }
    }

    /// Hides freq/dB/PRE/dB-unit labels and the title bar when a skin is loaded.
    /// All these labels are baked into eqmain.bmp; the title bar is replaced by
    /// the eqmain title strip.
    private func applySkinVisibility() {
        let active = WinampTheme.skinIsActive
        titleBar.isHidden = active
        for label in bandLabels { label.isHidden = active }
        for label in dbLabels { label.isHidden = active }
        preLabel?.isHidden = active
        dbUnitLabel?.isHidden = active
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if !WinampTheme.skinIsActive {
            drawUnskinnedDecorations()
        }
        guard WinampTheme.skinIsActive else { return }
        let ctx = NSGraphicsContext.current
        let prev = ctx?.imageInterpolation
        ctx?.imageInterpolation = .none
        defer { if let prev = prev { ctx?.imageInterpolation = prev } }

        if let bg = WinampTheme.sprite(.eqBackground) {
            // eqmain.bmp is 275×116; view is resized to 116 when skinned so the
            // sprite fills bounds exactly and sub-sprite coords match Webamp.
            bg.draw(in: bounds)
        }

        // Title bar overlay (y=0..14 of the EQ body is left empty for this).
        let isActive = window?.isKeyWindow ?? true
        if let tb = WinampTheme.sprite(.eqTitleBar(active: isActive)) {
            tb.draw(in: NSRect(x: 0, y: bounds.height - 14, width: bounds.width, height: 14))
        }
    }

    private func drawUnskinnedDecorations() {
        let pad: CGFloat = 4
        let preampX: CGFloat = pad + 6
        let sliderH: CGFloat = 56
        let controlsY = bounds.height - WinampTheme.titleBarHeight - 16
        let sliderAreaTop = controlsY - 10
        let sliderBottom = sliderAreaTop - sliderH

        // Five pale horizontal stripes running across the full EQ area
        // (preamp + bands), evenly spaced through the slider track — classic
        // eqmain.bmp pattern.
        let stripeColor = NSColor(white: 1.0, alpha: 0.08)
        stripeColor.setFill()
        let stripeX = preampX - 2
        let stripeEnd = bounds.width - pad
        let stripeW = max(0, stripeEnd - stripeX)
        let steps = 4
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let y = sliderBottom + t * sliderH
            NSRect(x: stripeX, y: y - 0.5, width: stripeW, height: 1).fill()
        }
    }

    override func layout() {
        super.layout()
        if WinampTheme.skinIsActive {
            layoutSkinned()
        } else {
            layoutUnskinned()
        }
    }

    /// Exact Webamp EQ pixel coordinates. View bounds are 275x116 when skinned.
    /// Y converted from Webamp top-down to AppKit bottom-up: y = 116 - y_webamp - h.
    private func layoutSkinned() {
        let h: CGFloat = bounds.height  // 116

        // Title bar (hidden but keep frame valid)
        titleBar.frame = NSRect(x: 0, y: h - 14, width: bounds.width, height: 14)

        // ON button: webamp (14, 18, 26, 12) → y = 116-18-12 = 86
        onButton.frame = NSRect(x: 14, y: 86, width: 26, height: 12)
        // AUTO button: webamp (39, 18, 33, 12) → y = 86
        autoButton.frame = NSRect(x: 39, y: 86, width: 33, height: 12)
        // PRESETS button: webamp (217, 18, 44, 12) → y = 86
        presetsButton.frame = NSRect(x: 217, y: 86, width: 44, height: 12)

        // EQ graph: webamp (86, 17, 113, 19) → y = 116-17-19 = 80
        responseView.frame = NSRect(x: 86, y: 80, width: 113, height: 19)

        // Preamp slider: webamp (21, 38, 14, 63) → y = 116-38-63 = 15
        preampSlider.frame = NSRect(x: 21, y: 15, width: 14, height: 63)

        // Band sliders: webamp x = 78 + i*18, y = 38, each 14x63 → y = 15
        for i in 0..<10 {
            bandSliders[i].frame = NSRect(x: 78 + CGFloat(i) * 18, y: 15, width: 14, height: 63)
        }

        // Hidden labels — collapse
        for label in bandLabels { label.frame = .zero }
        for label in dbLabels { label.frame = .zero }
        preLabel?.frame = .zero
        dbUnitLabel?.frame = .zero
    }

    private func layoutUnskinned() {
        let w = bounds.width
        let pad: CGFloat = 4

        titleBar.frame = NSRect(x: 0, y: bounds.height - WinampTheme.titleBarHeight,
                                width: w, height: WinampTheme.titleBarHeight)

        let controlsY = bounds.height - WinampTheme.titleBarHeight - 16
        onButton.frame = NSRect(x: pad, y: controlsY, width: 26, height: 14)
        autoButton.frame = NSRect(x: pad + 28, y: controlsY, width: 30, height: 14)
        presetsButton.frame = NSRect(x: w - pad - 50, y: controlsY, width: 50, height: 14)

        // Response view lives in the controls row, between AUTO and PRESETS.
        let respGap: CGFloat = 6
        let respX = autoButton.frame.maxX + respGap
        let respWidth = presetsButton.frame.minX - respX - respGap
        let respH: CGFloat = 19
        let titleBottom = bounds.height - WinampTheme.titleBarHeight
        let respY = titleBottom - 3 - respH
        responseView.frame = NSRect(x: respX, y: respY, width: max(0, respWidth), height: respH)

        let sliderH: CGFloat = 56
        let sliderAreaTop = controlsY - 10

        // Preamp on the leftmost column (right-shifted a few px for breathing room)
        let preampX: CGFloat = pad + 6
        preampSlider.frame = NSRect(x: preampX, y: sliderAreaTop - sliderH, width: 12, height: sliderH)
        viewWithTag(210)?.frame = NSRect(x: preampX - 14, y: sliderAreaTop - sliderH - 14, width: 40, height: 10)

        // dB labels — right of preamp slider
        let dbLabelW: CGFloat = 26
        let dbLabelX = preampX + 14
        viewWithTag(200)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - 10, width: dbLabelW, height: 10)
        viewWithTag(201)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - sliderH / 2 - 5, width: dbLabelW, height: 10)
        viewWithTag(202)?.frame = NSRect(x: dbLabelX, y: sliderAreaTop - sliderH, width: dbLabelW, height: 10)
        viewWithTag(211)?.frame = .zero

        // Band sliders
        let bandsStart = dbLabelX + dbLabelW + 2
        let bandsWidth = w - bandsStart - pad
        let bandSpacing = bandsWidth / CGFloat(10)

        for i in 0..<10 {
            let x = bandsStart + CGFloat(i) * bandSpacing + (bandSpacing - 12) / 2
            bandSliders[i].frame = NSRect(x: x, y: sliderAreaTop - sliderH, width: 12, height: sliderH)
            bandLabels[i].frame = NSRect(x: x - 4, y: sliderAreaTop - sliderH - 14, width: 20, height: 10)
        }
    }

    func bindToModel(audioEngine: AudioEngine, playlistManager: PlaylistManager? = nil) {
        self.audioEngine = audioEngine

        // Sync sliders and response curve from the audio engine's current state
        for (i, slider) in bandSliders.enumerated() {
            slider.value = audioEngine.eqBands[i]
        }
        preampSlider.value = audioEngine.preampGain
        responseView.bands = audioEngine.eqBands

        audioEngine.$eqEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.onButton.isActive = enabled }
            .store(in: &cancellables)

        // Keep response curve in sync with any band changes (presets, external updates)
        audioEngine.$eqBands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bands in self?.responseView.bands = bands }
            .store(in: &cancellables)

        // AUTO mode: match genre to preset when track changes
        if let pm = playlistManager {
            pm.$currentIndex
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.autoApplyPreset(for: pm.currentTrack) }
                .store(in: &cancellables)
        }
    }

    private func autoApplyPreset(for track: Track?) {
        guard autoButton.isActive, let genre = track?.genre.lowercased(), !genre.isEmpty else { return }
        let genrePresetMap: [String: String] = [
            "blues":             "Jazz",
            "classicrock":       "Rock",
            "country":           "Acoustic",
            "dance":             "Dance",
            "disco":             "Dance",
            "funk":              "R&B",
            "grunge":            "Rock",
            "hip-hop":           "Hip-Hop",
            "jazz":              "Jazz",
            "metal":             "Rock",
            "new age":           "Deep",
            "oldies":            "Rock",
            "other":             "Loudness",
            "pop":               "Pop",
            "r&b":               "R&B",
            "rap":               "Hip-Hop",
            "reggae":            "Latin",
            "rock":              "Rock",
            "techno":            "Electronic",
            "industrial":        "Electronic",
            "alternative":       "Rock",
            "ska":               "Latin",
            "death metal":       "Rock",
            "pranks":            "Spoken Word",
            "soundtrack":        "Classical",
            "euro-techno":       "Electronic",
            "ambient":           "Deep",
            "trip-hop":          "Hip-Hop",
            "vocal":             "Increase Vocals",
            "jazz+funk":         "Jazz",
            "fusion":            "Jazz",
            "trance":            "Electronic",
            "classical":         "Classical",
            "instrumental":      "Loudness",
            "acid":              "Electronic",
            "house":             "Dance",
            "game":              "Flat",
            "sound clip":        "Flat",
            "gospel":            "Increase Vocals",
            "noise":             "Flat",
            "alternrock":        "Rock",
            "bass":              "Increase Bass",
            "soul":              "R&B",
            "punk":              "Rock",
            "space":             "Deep",
            "meditative":        "Deep",
            "instrumental pop":  "Pop",
            "instrumental rock": "Rock",
            "ethnic":            "Acoustic",
            "gothic":            "Rock",
            "darkwave":          "Electronic",
            "techno-industrial": "Electronic",
            "electronic":        "Electronic",
            "pop-folk":          "Acoustic",
            "eurodance":         "Dance",
            "dream":             "Deep",
            "southern rock":     "Rock",
            "comedy":            "Spoken Word",
            "cult":              "Loudness",
            "gangsta":           "Hip-Hop",
            "top 40":            "Pop",
            "christian rap":     "Hip-Hop",
            "pop/funk":          "Pop",
            "jungle":            "Electronic",
            "native american":   "Acoustic",
            "cabaret":           "Increase Vocals",
            "new wave":          "Electronic",
            "psychadelic":       "Rock",
            "rave":              "Dance",
            "showtunes":         "Increase Vocals",
            "trailer":           "Loudness",
            "lo-fi":             "Deep",
            "tribal":            "Dance",
            "acid punk":         "Rock",
            "acid jazz":         "Jazz",
            "polka":             "Acoustic",
            "retro":             "Loudness",
            "musical":           "Increase Vocals",
            "rock & roll":       "Rock",
            "hard rock":         "Rock"
        ]
        let presetName = genrePresetMap.first { genre.contains($0.key) }?.value ?? "Flat"
        if let preset = EQPreset.presets.first(where: { $0.name == presetName }) {
            audioEngine?.setAllEQBands(preset.bands)
            for (i, slider) in bandSliders.enumerated() {
                slider.value = preset.bands[i]
            }
            responseView.bands = preset.bands
        }
    }

    private func showPresetsMenu() {
        let menu = NSMenu()
        for preset in EQPreset.presets {
            let item = NSMenuItem(title: preset.name, action: #selector(applyPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(title: "Reset to Default", action: #selector(resetToDefault), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.popUp(positioning: nil, at: NSPoint(x: presetsButton.frame.minX, y: presetsButton.frame.minY), in: self)
    }

    @objc private func resetToDefault() {
        guard let flat = EQPreset.presets.first(where: { $0.name == "Flat" }) else { return }
        audioEngine?.setAllEQBands(flat.bands)
        for (i, slider) in bandSliders.enumerated() {
            slider.value = flat.bands[i]
        }
        responseView.bands = flat.bands
    }

    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? EQPreset else { return }
        audioEngine?.setAllEQBands(preset.bands)
        for (i, slider) in bandSliders.enumerated() {
            slider.value = preset.bands[i]
        }
        responseView.bands = preset.bands
    }

    // MARK: - Window dragging (skinned mode)
    override func mouseDown(with event: NSEvent) {
        guard WinampTheme.skinIsActive else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        guard point.y >= bounds.height - 14 else { super.mouseDown(with: event); return }
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
