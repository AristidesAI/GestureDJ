import AVFoundation
import Combine
import UIKit

@MainActor
class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    var session: AVCaptureSession { captureSession }
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.gestureflow.sessionQueue")
    private var rotationCoordinator: AVCaptureDeviceRotationCoordinator?
    
    // Publishes the pixel buffer for consumption by the VisionEngine.
    nonisolated let pixelBufferPublisher = PassthroughSubject<CVPixelBuffer, Never>()
    
    @Published var isSessionRunning = false
    @Published var permissionGranted = false
    
    private(set) lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        return preview
    }()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupSession()
    }
    
    // MARK: - Session Management
    
    func requestPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // Already authorized
            self.permissionGranted = true
        case .notDetermined:
            // Request permission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    self.permissionGranted = granted
                    if granted {
                        self.startSession()
                    }
                }
            }
        case .denied, .restricted:
            // Permission denied or restricted
            self.permissionGranted = false
        @unknown default:
            self.permissionGranted = false
        }
    }
    
    private func setupSession() {
        Task { @MainActor in
            captureSession.beginConfiguration()

            // ARCHITECTURE FIX: Prevent camera from resetting the audio session.
            // This is required when using AVAudioEngine alongside AVCaptureSession.
            captureSession.automaticallyConfiguresApplicationAudioSession = false

            // Set session preset for a balance of performance and quality.
            captureSession.sessionPreset = .high

            // Configure camera input - preferring the widest available front camera for larger FOV
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )

            guard let videoDevice = discovery.devices.first,
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  captureSession.canAddInput(videoDeviceInput) else {
                print("Error: Could not create video device input.")
                captureSession.commitConfiguration()
                return
            }
            captureSession.addInput(videoDeviceInput)

            // Initialize rotation coordinator
            rotationCoordinator = AVCaptureDeviceRotationCoordinator(device: videoDevice, previewLayer: previewLayer)

            // Configure video output.
            if captureSession.canAddOutput(videoOutput) {
                await withCheckedContinuation { continuation in
                    sessionQueue.async {
                        self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                        continuation.resume()
                    }
                }
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                captureSession.addOutput(videoOutput)

                // Set initial rotation angle for the video output connection
                if let connection = videoOutput.connection(with: .video),
                   let coordinator = rotationCoordinator {
                    if connection.isVideoRotationAngleSupported(coordinator.videoRotationAngleForHorizonLevelCapture) {
                        connection.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                    }
                }
            }

            captureSession.commitConfiguration()
        }
    }
    
    func startSession() {
        if !captureSession.isRunning {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.captureSession.startRunning()
                    self.isSessionRunning = true
                }
            }
        }
    }
    
    func updateOrientation(_ orientation: UIDeviceOrientation) {
        Task { @MainActor in
            guard let connection = videoOutput.connection(with: .video),
                  let coordinator = rotationCoordinator else { return }

            let rotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture

            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                    self.isSessionRunning = false
                }
            }
        }
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        pixelBufferPublisher.send(pixelBuffer)
    }
}
