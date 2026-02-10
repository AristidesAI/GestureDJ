import Foundation
import Combine
import AVFoundation
import Vision

class AppCoordinator: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var selectedTab = 1
    @Published var isShowingLibrary = false
    @Published var selectedTrackTitle: String?
    @Published var isPlaying = false
    @Published var showInstructions = false
    
    // MARK: - Core Services
    @MainActor let cameraManager = CameraManager()
    let visionEngine: VisionEngine
    let audioManager = AudioManager()
    
    // MARK: - Settings State
    @Published var sensitivity: String = "High"
    @Published var smoothing: Double = 0.05
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
        self.visionEngine = VisionEngine(pixelBufferPublisher: cameraManager.pixelBufferPublisher.eraseToAnyPublisher())
        
        setupSubscriptions()
        
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
        if isPlaying {
            // Pitch -> Left Hand
            if let currentL = leftDist, let baselineL = baselineLeftDist {
                let delta = Float(currentL - baselineL)
                let sens: Float = sensitivity == "High" ? 6.0 : (sensitivity == "Medium" ? 4.0 : 2.0)
                let targetPitch = delta * 1200.0 * sens // Narrower range but faster reaction
                
                // Responsive smoothing
                currentPitch = currentPitch + (targetPitch - currentPitch) * 0.85
                audioManager.setPitch(currentPitch)
            }
            
            // Speed -> Right Hand
            if let currentR = rightDist, let baselineR = baselineRightDist {
                let delta = Float(currentR - baselineR)
                let sens: Float = sensitivity == "High" ? 4.0 : (sensitivity == "Medium" ? 2.5 : 1.5)
                let targetSpeed = 1.0 + (delta * sens)
                
                // Allow up to 4x speed, floor at 0.1x
                currentSpeed = max(0.1, min(currentSpeed + (targetSpeed - currentSpeed) * 0.85, 4.0))
                audioManager.setSpeed(currentSpeed)
            }
        }
    }
    
    private func calculateDistance(_ hand: HandLandmarks) -> CGFloat? {
        guard let thumb = hand.thumbTip, let index = hand.indexTip else { return nil }
        return sqrt(pow(thumb.x - index.x, 2) + pow(thumb.y - index.y, 2))
    }
        
    // MARK: - Settings Handlers
    func cycleSensitivity() {
        let options = ["Low", "Medium", "High"]
        if let index = options.firstIndex(of: sensitivity) {
            sensitivity = options[(index + 1) % options.count]
        }
    }
    
    func cycleSmoothing() {
        let options = [0.01, 0.05, 0.1, 0.2]
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
