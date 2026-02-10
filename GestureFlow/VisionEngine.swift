import Vision
import Combine
import SwiftUI

// A structure to hold the landmarks for a single hand.
struct HandLandmarks {
    let chirality: VNChirality
    let thumbTip: CGPoint?
    let indexTip: CGPoint?
    let middleTip: CGPoint?
    let wrist: CGPoint?
}

class VisionEngine: ObservableObject {
    
    // MARK: - Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var smoothedLandmarks: [VNChirality: HandLandmarks] = [:]
    private let smoothingFactor: CGFloat = 0.6
    private let jumpThreshold: CGFloat = 0.15 // 15% of frame
    private let visionQueue = DispatchQueue(label: "com.gestureflow.visionQueue")
    
    @Published var handLandmarks: [HandLandmarks] = []
    
    // MARK: - Initialization
    
    init(pixelBufferPublisher: AnyPublisher<CVPixelBuffer, Never>) {
        pixelBufferPublisher
            .subscribe(on: visionQueue)
            .sink { [weak self] pixelBuffer in
                self?.processFrame(pixelBuffer)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Vision Processing
    
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 2
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observations = request.results, !observations.isEmpty else {
                DispatchQueue.main.async { 
                    self.handLandmarks = [] 
                    self.smoothedLandmarks.removeAll()
                }
                return
            }
            
            var currentFrameLandmarks: [HandLandmarks] = []
            
            for observation in observations {
                let chirality = observation.chirality
                
                // Isolate thumb and index tips
                guard let thumbTipPoint = try? observation.recognizedPoint(.thumbTip),
                      thumbTipPoint.confidence > 0.3,
                      let indexTipPoint = try? observation.recognizedPoint(.indexTip),
                      indexTipPoint.confidence > 0.3 else { continue }
                
                let middleTipPoint = try? observation.recognizedPoint(.middleTip) // Silent tracking
                
                let thumbLoc = thumbTipPoint.location
                let indexLoc = indexTipPoint.location
                let middleLoc = middleTipPoint?.confidence ?? 0 > 0.3 ? middleTipPoint?.location : nil
                let wristLoc = (try? observation.recognizedPoint(.wrist))?.location
                
                // Apply exponential moving average smoothing
                let finalizedThumb: CGPoint
                let finalizedIndex: CGPoint
                
                if let previous = smoothedLandmarks[chirality] {
                    finalizedThumb = applySmoothing(current: thumbLoc, previous: previous.thumbTip ?? thumbLoc)
                    finalizedIndex = applySmoothing(current: indexLoc, previous: previous.indexTip ?? indexLoc)
                } else {
                    finalizedThumb = thumbLoc
                    finalizedIndex = indexLoc
                }
                
                let newLandmarks = HandLandmarks(
                    chirality: chirality,
                    thumbTip: finalizedThumb,
                    indexTip: finalizedIndex,
                    middleTip: middleLoc, // Silent anchor
                    wrist: wristLoc
                )
                
                smoothedLandmarks[chirality] = newLandmarks
                currentFrameLandmarks.append(newLandmarks)
            }
            
            DispatchQueue.main.async {
                self.handLandmarks = currentFrameLandmarks
            }
            
        } catch {
            print("Failed to perform Vision request: \(error)")
        }
    }
    
    private func applySmoothing(current: CGPoint, previous: CGPoint) -> CGPoint {
        // Jump Detection / Outlier Rejection
        let dx = abs(current.x - previous.x)
        let dy = abs(current.y - previous.y)
        
        // If the jump is too large, dampen the movement significantly to wait for "confirmation"
        let effectiveFactor: CGFloat
        if dx > jumpThreshold || dy > jumpThreshold {
            effectiveFactor = 0.1 // Slow down to wait for next frames
        } else {
            effectiveFactor = smoothingFactor
        }
        
        return CGPoint(
            x: previous.x + (current.x - previous.x) * effectiveFactor,
            y: previous.y + (current.y - previous.y) * effectiveFactor
        )
    }
}
