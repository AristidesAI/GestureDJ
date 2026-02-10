import Foundation
import Combine
import AVFoundation
import Vision
import SwiftUI // Added for withAnimation

class AppCoordinator: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var selectedTab = 1
    @Published var isShowingLibrary = false
    @Published var selectedTrackTitle: String?
    @Published var isPlaying: Bool = false
    @Published var showInstructions: Bool = true
    @Published var orientation: UIDeviceOrientation = .portrait
    
    // MARK: - App Icon / Launch Screen
    @MainActor let cameraManager = CameraManager()
    let visionEngine: VisionEngine
    let audioManager = AudioManager()
    let recordManager = RecordManager()
    
    // MARK: - Settings State
    @Published var sensitivity: String = "Standard"
    @Published var smoothing: Double = 0.20
    @Published var noHandsDelay: Double = 1.0
    
    // MARK: - Gesture Control State
    @Published var baselineLeftDist: CGFloat?
    @Published var baselineRightDist: CGFloat?
    @Published var currentPitch: Float = 0.0
    @Published var currentSpeed: Float = 1.0
    
    // MARK: - State Management
    private var cancellables = Set<AnyCancellable>()
    private var noHandsTimer: Timer?
    
    init() {
        // The VisionEngine listens to the camera's video stream.
        visionEngine = VisionEngine(pixelBufferPublisher: cameraManager.pixelBufferPublisher.eraseToAnyPublisher())
        
        setupSubscriptions()
        // Monitor tab changes to stop recording
        $selectedTab
            .sink { [weak self] _ in
                if self?.recordManager.isRecording == true {
                    self?.stopRecording()
                }
            }
            .store(in: &cancellables)
            
        // Feed video frames to recorder
        cameraManager.pixelBufferPublisher
            .sink { [weak self] buffer in
                if self?.recordManager.isRecording == true {
                    self?.recordManager.processVideoFrame(buffer, at: CMTime(value: Int64(Date().timeIntervalSince1970 * 1000), timescale: 1000))
                }
            }
            .store(in: &cancellables)
        setupOrientationMonitoring()
        
        Task { @MainActor in
            cameraManager.requestPermission()
            // Start the camera session as soon as the app launches.
            cameraManager.startSession()
        }
    }
    
    private func setupSubscriptions() {
        // Observe permission changes to trigger UI updates
        cameraManager.$permissionGranted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        // Subscribe to hand landmark updates from the VisionEngine.
        visionEngine.$handLandmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] landmarks in
                self?.handleHandDetection(landmarks)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - User Intent Handlers
    func openLibrary() {
        isShowingLibrary = true
    }
    
    func didSelectAudio(url: URL, title: String) {
        selectedTrackTitle = title
        isShowingLibrary = false
        selectedTab = 1
        
        // Load and play in the background
        Task {
            audioManager.loadTrack(url: url, strategy: .local)
            
            // Wait a tiny bit for the engine to settle before showing instructions
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            await MainActor.run {
                self.isPlaying = true
                self.showInstructions = true
            }
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            audioManager.pause()
            if recordManager.isRecording {
                stopRecording()
            }
        } else {
            // A track must be loaded to play.
            guard audioManager.isTrackLoaded else { return }
            audioManager.play()
        }
        isPlaying.toggle()
    }
    
    // MARK: - Core Logic
    private func handleHandDetection(_ landmarks: [HandLandmarks]) {
        // "No-Hands" Auto-Pause/Stop Logic
        if landmarks.isEmpty {
            if isPlaying && noHandsTimer == nil {
                noHandsTimer = Timer.scheduledTimer(withTimeInterval: noHandsDelay, repeats: false) { _ in
                    self.audioManager.pause()
                    self.isPlaying = false
                    self.baselineLeftDist = nil
                    self.baselineRightDist = nil
                }
            }
            return
        }
        
        // Hands are detected
        noHandsTimer?.invalidate()
        noHandsTimer = nil
        
        let leftHand = landmarks.first(where: { $0.chirality == .left })
        let rightHand = landmarks.first(where: { $0.chirality == .right })
        
        // Handle individual hand loss for auto-rebalance on return
        if leftHand == nil {
            baselineLeftDist = nil
        }
        if rightHand == nil {
            baselineRightDist = nil
        }
        
        // Reset baselines if a hand was previously lost and is now back (Auto-Rebalance)
        if leftHand != nil && baselineLeftDist == nil {
            baselineLeftDist = leftHand.flatMap { calculateDistance($0) }
            currentPitch = 0
            audioManager.setPitch(0)
        }
        if rightHand != nil && baselineRightDist == nil {
            baselineRightDist = rightHand.flatMap { calculateDistance($0) }
            currentSpeed = 1.0
            audioManager.setSpeed(1.0)
        }
        
        let leftDist = leftHand.flatMap { calculateDistance($0) }
        let rightDist = rightHand.flatMap { calculateDistance($0) }
        
        // Calibration logic: Save baseline distance when hands first detected
        if showInstructions && landmarks.count >= 2 {
            if let l = leftDist, let r = rightDist {
                showInstructions = false
                baselineLeftDist = l
                baselineRightDist = r
                if !isPlaying {
                    audioManager.play()
                    isPlaying = true
                }
            }
        }
        
        // Warp control logic
        // Pitch -> Left Hand
        if let currentL = leftDist, let baselineL = baselineLeftDist {
            let delta = Float(currentL - baselineL)
            let sens: Float = sensitivity == "Standard" ? 4.5 : (sensitivity == "High" ? 7.5 : 12.0)
            let targetPitch = delta * 1200.0 * sens // Reduced sensitivity
            
            // Responsive smoothing
            currentPitch = currentPitch + (targetPitch - currentPitch) * Float(smoothing)
            audioManager.setPitch(currentPitch)
        }
        
        // Speed -> Right Hand
        if let currentR = rightDist, let baselineR = baselineRightDist {
            let delta = Float(currentR - baselineR)
            let sens: Float = sensitivity == "Standard" ? 5.0 : (sensitivity == "High" ? 8.0 : 12.0)
            let targetSpeed = 1.0 + (delta * sens)
            
            // Allow up to 4x speed, floor at 0.1x
            currentSpeed = max(0.1, min(currentSpeed + (targetSpeed - currentSpeed) * Float(smoothing), 4.0))
            audioManager.setSpeed(currentSpeed)
        }
    }
    
    func restartTrack() {
        audioManager.restart()
        currentPitch = 0
        currentSpeed = 1.0
        audioManager.setPitch(0)
        audioManager.setSpeed(1.0)
    }
    
    func rebalanceControls() {
        // Re-calibrates the current hand distance as the "new zero"
        // Works for one or both hands, allowing rebalance while one hand touches the UI
        let currentLandmarks = visionEngine.handLandmarks
        let leftHand = currentLandmarks.first(where: { $0.chirality == .left })
        let rightHand = currentLandmarks.first(where: { $0.chirality == .right })
        
        if let l = leftHand.flatMap({ calculateDistance($0) }) {
            baselineLeftDist = l
            currentPitch = 0
            audioManager.setPitch(0)
        }
        if let r = rightHand.flatMap({ calculateDistance($0) }) {
            baselineRightDist = r
            currentSpeed = 1.0
            audioManager.setSpeed(1.0)
        }
    }
    
    // MARK: - Recording
    
    func toggleRecording() {
        if recordManager.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let mixer = audioManager.getMainMixerNode() else { return }
        
        // Video Settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1080,
            AVVideoHeightKey: 1920
        ]
        
        // Audio Settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]
        
        recordManager.startRecording(videoSettings: videoSettings, audioSettings: audioSettings)
        
        // Start Audio Tap
        mixer.installTap(onBus: 0, bufferSize: 1024, format: mixer.outputFormat(forBus: 0)) { [weak self] buffer, time in
            self?.recordManager.processAudioBuffer(buffer, at: time)
        }
    }
    
    private func stopRecording() {
        guard let mixer = audioManager.getMainMixerNode() else { return }
        mixer.removeTap(onBus: 0)
        
        recordManager.stopRecording { url in
            print("Recording saved to: \(url?.path ?? "unknown")")
        }
    }
    
    private func calculateDistance(_ hand: HandLandmarks) -> CGFloat? {
        guard let thumb = hand.thumbTip, let index = hand.indexTip else { return nil }
        return sqrt(pow(thumb.x - index.x, 2) + pow(thumb.y - index.y, 2))
    }
    
    private func setupOrientationMonitoring() {
        self.orientation = UIDevice.current.orientation
        
        NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            let newOrientation = UIDevice.current.orientation
            if newOrientation.isValidInterfaceOrientation {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    self?.orientation = newOrientation
                }
            }
        }
    }
        
    // MARK: - Settings Handlers
    func cycleSensitivity() {
        let options = ["Standard", "High", "Extreme"]
        if let index = options.firstIndex(of: sensitivity) {
            sensitivity = options[(index + 1) % options.count]
        }
    }
    
    func cycleSmoothing() {
        let options = [0.05, 0.1, 0.2, 0.35, 0.5]
        if let index = options.firstIndex(of: smoothing) {
            smoothing = options[(index + 1) % options.count]
        }
    }
    
    func cycleNoHandsDelay() {
        let options = [0.5, 1.0, 2.0, 5.0]
        if let index = options.firstIndex(of: noHandsDelay) {
            noHandsDelay = options[(index + 1) % options.count]
        }
    }
}
