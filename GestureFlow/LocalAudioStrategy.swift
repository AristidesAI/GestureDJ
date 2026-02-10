import AVFoundation

protocol AudioStrategy {
    func play(trackURL: URL)
    func pause()
    func resume()
    func stop()
    func setSpeed(_ speed: Float)
    func setPitch(_ pitch: Float)
    func setVolume(_ volume: Float)
}

class LocalAudioStrategy: AudioStrategy {
    
    // MARK: - Properties
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    
    // MARK: - Initialization
    
    init() {
        setupAudioSession()
        setupEngine()
    }
    
    // MARK: - Audio Playback
    
    func play(trackURL: URL) {
        do {
            // Ensure audio session is active
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            
            // Stop if already playing
            stop()
            
            let audioFile = try AVAudioFile(forReading: trackURL)
            let format = audioFile.processingFormat
            
            // Disconnect old connections to prevent graph issues
            engine.disconnectNodeOutput(playerNode)
            engine.disconnectNodeOutput(timePitchNode)
            engine.disconnectNodeInput(engine.mainMixerNode)
            
            // Connect: Player -> Pitch -> Mixer -> Output
            engine.connect(playerNode, to: timePitchNode, format: format)
            engine.connect(timePitchNode, to: engine.mainMixerNode, format: format)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
            
            // Prepare and play the file
            playerNode.scheduleFile(audioFile, at: nil)
            
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            
            playerNode.play()
            
        } catch {
            print("AVAudioEngine Error: \(error.localizedDescription)")
        }
    }
    
    func pause() {
        playerNode.pause()
    }
    
    func resume() {
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()
    }
    
    func stop() {
        playerNode.stop()
        engine.stop()
    }
    
    // MARK: - DSP Controls
    
    func setSpeed(_ speed: Float) {
        // Clamp the rate to a usable range.
        timePitchNode.rate = max(0.1, min(speed, 2.0))
    }
    
    func setPitch(_ pitch: Float) {
        // Cents, range from -2400 to 2400.
        timePitchNode.pitch = pitch
    }
    
    func setVolume(_ volume: Float) {
        playerNode.volume = max(0.0, min(volume, 1.0))
    }
    
    // MARK: - Private Helpers
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(timePitchNode)
        // Do NOT call prepare() here yet, wait for connections in play()
    }
}
