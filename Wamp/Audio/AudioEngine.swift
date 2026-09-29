import Foundation
import AVFoundation
import Combine
import Accelerate

enum RepeatMode: Int, Codable {
    case off = 0
    case track = 1
    case playlist = 2
}

enum PlayState {
    case stopped
    case playing
    case paused
}

extension Notification.Name {
    static let trackDidFinish = Notification.Name("trackDidFinish")
}

extension AudioEngine {
    /// userInfo key on `.trackDidFinish`: true when the engine has already
    /// promoted a queued gapless segment and audio is continuing seamlessly —
    /// the playlist should only advance its index, not start playback anew.
    static let gaplessChainedKey = "gaplessChained"
}

extension AudioEngine: RadioStreamDelegate {
    func radioStream(_ stream: RadioStream,didReceiveAudio data: Data) {
        radioQueue.async { [weak self] in
            self?.radioParser?.parse(data)
        }
    }
    func radioStream(_ stream: RadioStream, didReceiveStationTitle title: String) {
        DispatchQueue.main.async {
            self.stationTitle = title
        }
    }
    func radioStream(_ stream: RadioStream, didReceiveStreamTitle title: String) {
        DispatchQueue.main.async {
            self.streamTitle = title
        }
    }
    func radioStream(_ stream: RadioStream, didReceiveBitrate bitrate: Int) {
        DispatchQueue.main.async {
            self.radioBitrate = bitrate
        }
    }
    func radioStream(_ stream: RadioStream, didFail error: Error) {
        debugLog("🔴 Radio network error:", error)
        DispatchQueue.main.async {
            self.radioBuffering = false
        }
    }
}

extension AudioEngine: RadioAudioParserDelegate {
    func radioAudioParser(_ parser: RadioAudioParser, didFindMagicCookie cookie: Data) {
        radioQueue.async { [weak self] in
            guard let self else { return }

            self.radioMagicCookie = cookie
            self.radioDecoder?.setMagicCookie(cookie)
        }
    }
    
    func radioAudioParser(_ parser: RadioAudioParser, didFindFormat format: AVAudioFormat) {
        radioQueue.async { [weak self] in
            guard let self else { return }
            guard self.radioDecoder == nil else { return }
            
            let streamSampleRate = Int(format.sampleRate.rounded())
            DispatchQueue.main.async {
                self.radioSampleRate = streamSampleRate
            }
            
            let eqInputFormat = self.eq.inputFormat(forBus: 0)

            // Radio PCM must match the sample rate of the graph at the point
            // where the player node feeds the EQ.
            //
            // AVAudioConverter therefore performs:
            // compressed stream rate -> player/EQ graph rate
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: eqInputFormat.sampleRate,
                channels: format.channelCount,
                interleaved: false
            ) else {
                debugLog("🔴 Could not create radio output format")
                return
            }

            let decoder = RadioDecoder(inputFormat: format,outputFormat: outputFormat)

            guard let decoder else {
                debugLog("🔴 Could not create RadioDecoder")
                return
            }

            if let cookie = self.radioMagicCookie {
                decoder.setMagicCookie(cookie)
            }

            self.radioDecoder = decoder
            self.audioSampleRate = outputFormat.sampleRate
        }
    }

    func radioAudioParser(_ parser: RadioAudioParser, didReceive data: Data, packetDescriptions: [AudioStreamPacketDescription]) {
        radioQueue.async { [weak self] in
            guard let self, let decoder = self.radioDecoder,
                  let pcm = decoder.decode(data: data, packetDescriptions:packetDescriptions) else { return }
            self.scheduleRadioBuffer(pcm)
        }
    }

    func radioAudioParser(_ parser: RadioAudioParser, didFail status: OSStatus) {
        debugLog("🔴 AudioFileStream:", status)
    }
}

class AudioEngine: ObservableObject {
    var maxSpectrumBars = 0 // unskinned = 26, skinned = 19, set in MainPlayerView.layout
    // MARK: - Published State
    @Published var isPlaying = false
    @Published var playState: PlayState = .stopped
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 0.75 {
        didSet { engine.mainMixerNode.outputVolume = effectiveVolume }
    }
    @Published var balance: Float = 0 {
        didSet { playerNode.pan = balance }
    }
    @Published var isMuted = false {
        didSet { engine.mainMixerNode.outputVolume = effectiveVolume }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var eqEnabled = true {
        didSet { eq.bypass = !eqEnabled }
    }
    @Published var preampGain: Float = 0 // dB, -12 to +12
    @Published var spectrumData: [Float] = []

    // MARK: - EQ State
    @Published private(set) var eqBands: [Float] = Array(repeating: 0, count: 10) // dB per band

    static let eqFrequencies: [Float] = [
        32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
    ]

    // MARK: - Private
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let eq: AVAudioUnitEQ
    private var audioFile: AVAudioFile?
    private var seekFrame: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 44100
    private var audioLengthFrames: AVAudioFramePosition = 0
    private var timeUpdateTimer: Timer?
    private var needsScheduling = true
    private var playbackGeneration: UInt64 = 0
    /// Upper frame bound of the segment currently scheduled. Matches
    /// `audioLengthFrames` for a whole-file play, or the CUE track's end frame
    /// when we're playing a bounded segment.
    private var currentSegmentEndFrame: AVAudioFramePosition = 0
    /// Logical start frame of the current track's segment (0 for whole-file
    /// playback, the CUE start frame for virtual tracks). Unlike `seekFrame`
    /// it is not moved by seeks — repeat-one loops back to it.
    private var currentSegmentStartFrame: AVAudioFramePosition = 0
    /// Set by `chainNextSegment` when a follow-up segment has already been
    /// queued on the player node. Consumed by `handleTrackCompletion` so the
    /// engine keeps playing into the chained segment without re-loading.
    private var pendingChain: (startFrame: AVAudioFramePosition, endFrame: AVAudioFramePosition)?

    private var effectiveVolume: Float {
        isMuted ? 0 : volume
    }
    
    // MARK: - Spectrum FFT
    private var spectrumFFTSetup: FFTSetup?
    private var spectrumFFTSize = 0
    private var spectrumSampleRate: Float = 0
    private var spectrumBars = 0

    private var spectrumWindow: [Float] = []
    private var spectrumWindowed: [Float] = []
    private var spectrumReal: [Float] = []
    private var spectrumImag: [Float] = []
    private var spectrumMagnitudes: [Float] = []
    private var spectrumPower: [Float] = []

    /// FFT index ranges for the 19 displayed spectrum bars.
    private var spectrumRanges: [(start: Int, end: Int)] = []
    private let spectrumMinFrequency: Float = 32.0
    private let spectrumMaxFrequency: Float = 16_000.0
    private var spectrumNormalization: Float = 0
    private let spectrumDisplayCompression: Float = 0.5  // pow(amplitude, val) val = 1.0 = linear
    private let spectrumDisplayGain: Float = 4.5 // dB
    
    /// Radio streams
    private var radioStream: RadioStream?
    private var radioParser: RadioAudioParser?
    private var radioDecoder: RadioDecoder?
    private let radioQueue = DispatchQueue(label: "Wamp.RadioAudio")
    private var radioScheduledBuffers = 0
    private var radioPlaybackStarted = false
    private var radioMagicCookie: Data?

    @Published var isRadioStream = false
    @Published var stationTitle = ""
    @Published var streamTitle = ""
    @Published var radioBuffering = false
    @Published private(set) var radioBitrate: Int = 0
    @Published private(set) var radioSampleRate: Int = 0
    
    var radioDisplayTitle: String {
        let song = streamTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !song.isEmpty {
            return "\(song)"
        }
        return stationTitle
    }
    
    // MARK: - Init
    init() {
        eq = AVAudioUnitEQ(numberOfBands: 10)
        setupAudioChain()
        setupEQBands()
    }

    private func setupAudioChain() {
        engine.attach(playerNode)
        engine.attach(eq)

        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: eq, format: hardwareFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: hardwareFormat)

        engine.mainMixerNode.outputVolume = effectiveVolume
    }

    private func setupEQBands() {
        for (i, freq) in Self.eqFrequencies.enumerated() {
            let band = eq.bands[i]
            if i == 0 {
                band.filterType = .lowShelf
            } else if i == Self.eqFrequencies.count - 1 {
                band.filterType = .highShelf
            } else {
                band.filterType = .parametric
            }
            band.frequency = freq
            band.bandwidth = 1.0
            band.gain = 0
            band.bypass = false
        }
    }

    // MARK: - Playback Controls

    func load(url: URL, play: Bool = false, startTime: TimeInterval? = nil, endTime: TimeInterval? = nil) {
        stop()
        playbackGeneration &+= 1

        do {
            if let scheme = url.scheme?.lowercased() {
                if scheme == "http" || scheme == "https" {
                    isRadioStream = true
                }
            }
            if !isRadioStream {
                try loadFile(url: url)
            }
            // return, if only loading is requested
            guard play else { return }

            if !engine.isRunning {
                try engine.start()
            }
            installSpectrumTap()

            // start playing, either with segment or without
            if let startTime = startTime {
                let startFrame = AVAudioFramePosition(startTime * audioSampleRate)
                let endFrame: AVAudioFramePosition
                if let endTime = endTime {
                    endFrame = min(audioLengthFrames, AVAudioFramePosition(endTime * audioSampleRate))
                } else {
                    endFrame = audioLengthFrames
                }
                
                seekFrame = max(0, min(startFrame, audioLengthFrames))
                currentSegmentStartFrame = seekFrame
                scheduleSegment(endFrame: endFrame)
            } else {
                scheduleAndPlay()
            }
        } catch {
            debugLog("🔴 AudioEngine: failed to load \(url.lastPathComponent): \(error)")
        }
    }

    
    /// Schedule a follow-up segment back-to-back on the same player node —
    /// no `stop()`, no reload — so the boundary is sample-exact. Returns true
    /// on success, false if the engine isn't currently playing this file.
    ///
    /// The chained segment's completion handler fires `.trackDidFinish` when
    /// the chained segment itself ends. When the *prior* segment ends its
    /// completion handler will also fire; it consumes `pendingChain` and
    /// updates the seek/end bookkeeping without interrupting playback.
    @discardableResult
    func chainNextSegment(url: URL, startTime: TimeInterval, endTime: TimeInterval?) -> Bool {
        guard isPlaying, let file = audioFile, file.url == url else { return false }
        let startFrame = AVAudioFramePosition(startTime * audioSampleRate)
        let endFrame: AVAudioFramePosition
        if let endTime = endTime {
            endFrame = min(audioLengthFrames, AVAudioFramePosition(endTime * audioSampleRate))
        } else {
            endFrame = audioLengthFrames
        }
        let frames = endFrame - startFrame
        guard frames > 0 else { return false }

        let generation = playbackGeneration
        playerNode.scheduleSegment(
            file,
            startingFrame: max(0, startFrame),
            frameCount: AVAudioFrameCount(frames),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTrackCompletion()
            }
        }
        pendingChain = (startFrame: max(0, startFrame), endFrame: endFrame)
        return true
    }

    /// Shared helper: opens the audio file and sets duration/sample-rate metadata.
    private func loadFile(url: URL) throws {
        audioFile = try AVAudioFile(forReading: url)
        guard let file = audioFile else {
            debugLog("🔴 loadFile: audioFile is nil after init")
            return
        }

        audioSampleRate = file.processingFormat.sampleRate
        audioLengthFrames = file.length
        duration = Double(audioLengthFrames) / audioSampleRate
        seekFrame = 0
        needsScheduling = true
        currentSegmentStartFrame = 0
        currentSegmentEndFrame = 0
        debugLog("🔵 loadFile: file loaded, sampleRate=\(audioSampleRate), frames=\(audioLengthFrames), duration=\(duration)s")
    }

    func play() {
        if isRadioStream {
                do {
                    if !engine.isRunning {
                        try engine.start()
                    }
                    installSpectrumTap()
                    playerNode.play()
                    isPlaying = true
                    playState = .playing
                } catch {
                    debugLog("AudioEngine: failed to resume radio:", error)
                }
                return
            }

        guard audioFile != nil else { return }
        do {
            if !engine.isRunning {
                try engine.start()
            }
            installSpectrumTap()
            if needsScheduling {
                // Respect the active CUE segment bound (set by a paused seek);
                // scheduling to EOF here would bleed past the cue track's end.
                scheduleSegment(endFrame: currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames)
            } else {
                playerNode.play()
            }
            isPlaying = true
            playState = .playing
            startTimeUpdates()
        } catch {
            debugLog("AudioEngine: failed to start: \(error)")
        }
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        playState = .paused
        stopTimeUpdates()
    }

    func stop() {
        debugLog("🟡 stop() called, gen=\(playbackGeneration), isPlaying=\(isPlaying)")
        // radio stream
        radioStream?.stop()
        radioStream = nil
        radioParser = nil
        radioDecoder = nil
        radioScheduledBuffers = 0
        radioPlaybackStarted = false
        radioBuffering = false
        isRadioStream = false
        stationTitle = ""
        streamTitle = ""
        radioBitrate = 0
        radioSampleRate = 0
        radioMagicCookie = nil

        playerNode.stop()
        isPlaying = false
        playState = .stopped
        currentTime = 0
        seekFrame = 0
        needsScheduling = true
        pendingChain = nil
        currentSegmentStartFrame = 0
        currentSegmentEndFrame = 0
        stopTimeUpdates()
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard !isRadioStream else { return }
        guard audioFile != nil else { return }
        let targetFrame = AVAudioFramePosition(time * audioSampleRate)
        let upperBound = currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames
        seekFrame = max(0, min(targetFrame, upperBound))
        needsScheduling = true
        // Rescheduling wipes the player node's queue, so any chained gapless
        // segment is gone — forget it, or completion bookkeeping derails.
        pendingChain = nil

        if isPlaying {
            scheduleSegment(endFrame: upperBound)
        } else {
            currentTime = time
        }
    }

    // MARK: - EQ
    func setEQ(band: Int, gain: Float) {
        guard band >= 0, band < 10 else { return }
        let clampedGain = max(-12, min(12, gain))
        eqBands[band] = clampedGain
        eq.bands[band].gain = clampedGain
    }

    func setPreamp(gain: Float) {
        preampGain = max(-12, min(12, gain))
        eq.globalGain = preampGain
    }

    func setAllEQBands(_ gains: [Float]) {
        for (i, gain) in gains.prefix(10).enumerated() {
            setEQ(band: i, gain: gain)
        }
    }

    func resetEQ() {
        setAllEQBands(Array(repeating: 0, count: 10))
        setPreamp(gain: 0)
    }

    // MARK: - Private Playback
    private func scheduleAndPlay() {
        scheduleSegment(endFrame: audioLengthFrames)
    }

    private func scheduleSegment(endFrame: AVAudioFramePosition) {
        guard let file = audioFile else {
            debugLog("🔴 scheduleSegment: no audioFile")
            return
        }
        let framesToPlay = endFrame - seekFrame
        debugLog("🟢 scheduleSegment: framesToPlay=\(framesToPlay), seekFrame=\(seekFrame), endFrame=\(endFrame), gen=\(playbackGeneration)")
        guard framesToPlay > 0 else {
            debugLog("🔴 scheduleSegment: no frames to play, calling handleTrackCompletion")
            handleTrackCompletion()
            return
        }

        // Invalidate completion handlers of whatever was scheduled before:
        // playerNode.stop() fires them asynchronously, and without the bump
        // they'd be mistaken for a genuine end-of-segment.
        playbackGeneration &+= 1
        playerNode.stop()
        let generation = playbackGeneration
        let capturedEnd = endFrame
        playerNode.scheduleSegment(
            file,
            startingFrame: seekFrame,
            frameCount: AVAudioFrameCount(framesToPlay),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackGeneration == generation else { return }
                self.handleTrackCompletion()
            }
        }
        playerNode.play()
        isPlaying = true
        playState = .playing
        needsScheduling = false
        currentSegmentEndFrame = capturedEnd
        startTimeUpdates()
    }

    private func handleTrackCompletion() {
        debugLog("🔴 handleTrackCompletion: isPlaying=\(isPlaying), repeatMode=\(repeatMode), gen=\(playbackGeneration)")
        guard isPlaying else {
            debugLog("🔴 handleTrackCompletion: NOT playing, ignoring")
            return
        }

        if repeatMode == .track {
            // Loop the current track's segment, not the whole file — for a CUE
            // virtual track that segment is a slice of the album file.
            pendingChain = nil
            seekFrame = currentSegmentStartFrame
            needsScheduling = true
            scheduleSegment(endFrame: currentSegmentEndFrame > 0 ? currentSegmentEndFrame : audioLengthFrames)
            return
        }

        // Gapless chain: the next segment is already queued on the player node
        // and may already be feeding audio. Adopt its bookkeeping and notify
        // the playlist, but do NOT stop or reset the engine.
        if let pending = pendingChain {
            // playerTime.sampleTime keeps counting across the chain boundary
            // (no node stop), so rebase seekFrame by the just-finished
            // segment's length — otherwise currentTime overcounts by it.
            let finishedLength = max(0, currentSegmentEndFrame - seekFrame)
            seekFrame = pending.startFrame - finishedLength
            currentSegmentStartFrame = pending.startFrame
            currentSegmentEndFrame = pending.endFrame
            pendingChain = nil
            debugLog("🟢 handleTrackCompletion: promoted chained segment [\(pending.startFrame), \(pending.endFrame)]")
            NotificationCenter.default.post(name: .trackDidFinish, object: nil,
                                            userInfo: [AudioEngine.gaplessChainedKey: true])
            return
        }

        isPlaying = false
        playState = .stopped
        stopTimeUpdates()
        debugLog("🔴 handleTrackCompletion: posting .trackDidFinish")
        NotificationCenter.default.post(name: .trackDidFinish, object: nil)
    }

    // MARK: - Time Updates
    private func startTimeUpdates() {
        stopTimeUpdates()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func stopTimeUpdates() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }

    private func updateCurrentTime() {
        guard isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
        currentTime = Double(seekFrame + playerTime.sampleTime) / audioSampleRate
    }

    // MARK: - Spectrum Tap
    private func installSpectrumTap() {
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        mixer.removeTap(onBus: 0)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processSpectrumData(buffer: buffer)
        }
    }

    private func prepareSpectrumFFT(fftSize: Int, sampleRate: Float) -> Bool {
        // Nothing changed -> reuse everything.
        if fftSize == spectrumFFTSize, sampleRate == spectrumSampleRate, spectrumFFTSetup != nil,
                maxSpectrumBars == spectrumBars, !spectrumRanges.isEmpty {
            return true
        }

        // Dispose old setup.
        if let setup = spectrumFFTSetup {
            vDSP_destroy_fftsetup(setup)
            spectrumFFTSetup = nil
        }
        
        let halfSize = fftSize / 2
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return false
        }

        spectrumFFTSetup = setup
        spectrumFFTSize = fftSize
        spectrumSampleRate = sampleRate
        spectrumBars = maxSpectrumBars

        // Allocate buffers only when FFT size changes.
        spectrumData = Array(repeating: 0, count: maxSpectrumBars)
        spectrumWindow = [Float](repeating: 0, count: fftSize)
        spectrumWindowed = [Float](repeating: 0, count: fftSize)
        spectrumReal = [Float](repeating: 0, count: halfSize)
        spectrumImag = [Float](repeating: 0, count: halfSize)
        spectrumPower = [Float](repeating: 0, count: halfSize)

        // Hann window only has to be generated once.
        vDSP_hann_window(&spectrumWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        // normalization
        vDSP_sve(spectrumWindow, 1, &spectrumNormalization, vDSP_Length(fftSize))

        // Precalculate FFT ranges for the spectrum bars.
        let frequencyPerBin = sampleRate / Float(fftSize)
        let maxFrequency = min(spectrumMaxFrequency, sampleRate * 0.5)
        let frequencyRatio = pow(maxFrequency / spectrumMinFrequency, 1.0 / Float(maxSpectrumBars))

        spectrumRanges.removeAll(keepingCapacity: true)
        spectrumRanges.reserveCapacity(maxSpectrumBars)

        for i in 0..<maxSpectrumBars {
            let lowerFrequency = spectrumMinFrequency * pow(frequencyRatio, Float(i))
            let upperFrequency = spectrumMinFrequency * pow(frequencyRatio, Float(i + 1))

            var start = Int(lowerFrequency / frequencyPerBin)
            var end = Int(upperFrequency / frequencyPerBin)
            start = max(1, min(start, halfSize - 1))
            end = max(start + 1, min(end, halfSize))

            spectrumRanges.append((start, end))
        }
        return true
    }
    
    private func processSpectrumData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0], maxSpectrumBars > 0 else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Use power-of-2 size for FFT
        let log2n = vDSP_Length(log2(Float(frameCount)))
        let fftSize = 1 << Int(log2n)
        let halfSize = fftSize / 2
        
        // The tap doesn't guarantee buffer sizes; with halfSize below the
        // maxSpectrumBars-bin output the mapping loop would form an empty range and trap.
        guard halfSize >= maxSpectrumBars else { return }
        
        let sampleRate = Float(buffer.format.sampleRate)
        guard prepareSpectrumFFT(fftSize: fftSize, sampleRate: sampleRate), let fftSetup = spectrumFFTSetup else {
            return
        }
        
        // Apply cached Hann window.
        vDSP_vmul(channelData, 1, spectrumWindow, 1, &spectrumWindowed, 1, vDSP_Length(fftSize))
        
        spectrumReal.withUnsafeMutableBufferPointer { realBuf in
            spectrumImag.withUnsafeMutableBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress, let imagBase = imagBuf.baseAddress else { return }

                var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)
                
                // Convert interleaved real samples to split complex.
                spectrumWindowed.withUnsafeBytes { rawBuffer in
                    let complexBuffer = rawBuffer.bindMemory(to: DSPComplex.self)
                    guard let complexBase = complexBuffer.baseAddress else { return }

                    vDSP_ctoz(complexBase, 2, &splitComplex, 1, vDSP_Length(halfSize))
                }

                // FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
                // Squared magnitudes = power of band
                vDSP_zvmags(&splitComplex, 1, &spectrumPower, 1, vDSP_Length(halfSize))
                
                let displayGain = pow(10, spectrumDisplayGain/20.0)
                var spectrum = [Float](repeating: 0, count: maxSpectrumBars)
                for i in 0..<maxSpectrumBars {
                    let range = spectrumRanges[i]
                    var bandPower: Float = 0
                    vDSP_sve(Array(spectrumPower[range.start..<range.end]), 1, &bandPower, vDSP_Length(range.end - range.start))
                    
                    let bandAmplitude = sqrt(bandPower)
                    let normalizedAmplitude = bandAmplitude / spectrumNormalization
                    spectrum[i] = min(1.0, pow(normalizedAmplitude, spectrumDisplayCompression) * displayGain)
                }

                DispatchQueue.main.async { [weak self] in
                    self?.spectrumData = spectrum
                }
            }
        }
    }

    // MARK: - Radio Streams
    func loadStream(url: URL, stationTitle: String? = nil, play: Bool = true) {
        stop()

        playbackGeneration &+= 1

        audioFile = nil
        duration = 0
        currentTime = 0
        seekFrame = 0

        isRadioStream = true
        stationTitle = ""
        streamTitle = ""
        radioBitrate = 0
        radioSampleRate = 0
        radioBuffering = true
        radioMagicCookie = nil

        radioScheduledBuffers = 0
        radioPlaybackStarted = false

        do {
            let parser = try RadioAudioParser()
            parser.delegate = self
            radioParser = parser

            let stream = RadioStream()
            stream.delegate = self
            radioStream = stream

            if !engine.isRunning {
                try engine.start()
            }

            installSpectrumTap()

            if play {
                stream.start(url: url)
            }

        } catch {
            debugLog("🔴 Failed to start radio:", error)
            isRadioStream = false
            radioBuffering = false
        }
    }

    private func scheduleRadioBuffer(_ buffer: AVAudioPCMBuffer) {
        radioScheduledBuffers += 1
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataConsumed)
        { [weak self] _ in
            guard let self else { return }

            self.radioQueue.async { self.radioScheduledBuffers = max(0, self.radioScheduledBuffers - 1) }
        }

        // Erste Version:
        // einige Decoder-Buffer puffern.
        if !radioPlaybackStarted, radioScheduledBuffers >= 5 {
            radioPlaybackStarted = true
            DispatchQueue.main.async {
                self.playerNode.play()
                self.isPlaying = true
                self.playState = .playing
                self.radioBuffering = false
            }
        }
    }
    
    deinit {
        if let setup = spectrumFFTSetup { vDSP_destroy_fftsetup(setup) }
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }
}
