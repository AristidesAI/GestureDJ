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
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.captureSession.beginConfiguration()

            // ARCHITECTURE FIX: Prevent camera from resetting the audio session.
            // This is required when using AVAudioEngine alongside AVCaptureSession.
            self.captureSession.automaticallyConfiguresApplicationAudioSession = false

            // Set session preset for a balance of performance and quality.
            self.captureSession.sessionPreset = .high

            // Configure camera input - preferring the widest available front camera for larger FOV
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )

            guard let videoDevice = discovery.devices.first,
                  let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoDeviceInput) else {
                print("Error: Could not create video device input.")
                self.captureSession.commitConfiguration()
                return
            }
            self.captureSession.addInput(videoDeviceInput)

            // Configure video output.
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.captureSession.addOutput(self.videoOutput)

                // Explicitly set portrait orientation for the video output connection
                if let connection = self.videoOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            }

            self.captureSession.commitConfiguration()
        }
    }

    func startSession() {
        if !captureSession.isRunning {
            sessionQueue.async {
                self.captureSession.startRunning()
                Task { @MainActor in
                    self.isSessionRunning = true
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                Task { @MainActor in
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
