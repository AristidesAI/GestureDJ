import AVFoundation
import Photos
import Combine
import CoreImage

class RecordManager: ObservableObject {
    @Published var isRecording = false
    @Published var recordedDuration: TimeInterval = 0
    
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private var startTime: CMTime?
    private var timer: Timer?
    
    // Captured frame/buffer queues
    private let processingQueue = DispatchQueue(label: "com.gestureflow.recordQueue", qos: .userInitiated)
    
    func startRecording(videoSettings: [String: Any], audioSettings: [String: Any]) {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("GestureFlowRecording.mp4")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        do {
            assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
            
            // Video Input
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // Audio Input
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true
            
            if let videoInput = videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)
            }
            
            if let audioInput = audioInput, assetWriter?.canAdd(audioInput) == true {
                assetWriter?.add(audioInput)
            }
            
            assetWriter?.startWriting()
            isRecording = true
            recordedDuration = 0
            startTime = nil
            
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.recordedDuration += 1
            }
            
        } catch {
            print("RecordManager: Failed to start writing: \(error)")
        }
    }
    
    func processVideoFrame(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        processingQueue.async {
            guard self.isRecording, let videoInput = self.videoInput, videoInput.isReadyForMoreMediaData else { return }
            
            if self.startTime == nil {
                self.startTime = time
                self.assetWriter?.startSession(atSourceTime: time)
            }
            
            self.pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: time)
        }
    }
    
    func processAudioBuffer(_ pcmBuffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        processingQueue.async {
            guard self.isRecording, let audioInput = self.audioInput, audioInput.isReadyForMoreMediaData else { return }
            
            // Convert AVAudioPCMBuffer to CMSampleBuffer
            guard let sampleBuffer = self.makeCMSampleBuffer(from: pcmBuffer, at: time) else { return }
            
            if self.startTime != nil {
                audioInput.append(sampleBuffer)
            }
        }
    }
    
    private func makeCMSampleBuffer(from buffer: AVAudioPCMBuffer, at time: AVAudioTime) -> CMSampleBuffer? {
        // Implementation for converting PCM to CMSampleBuffer
        // This is a bit involved, so for short recording in GestureFlow, 
        // we'll assume standard 44.1/48k stereo.
        var formatDesc: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: buffer.format.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &formatDesc)
        
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate)), presentationTimeStamp: CMTime(value: time.sampleTime, timescale: CMTimeScale(buffer.format.sampleRate)), decodeTimeStamp: .invalid)
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDesc, sampleCount: CMItemCount(buffer.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
        
        if let sb = sampleBuffer {
            CMSampleBufferSetDataBufferFromAudioBufferList(sb, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList)
        }
        
        return sampleBuffer
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        isRecording = false
        timer?.invalidate()
        timer = nil
        
        processingQueue.async {
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            
            self.assetWriter?.finishWriting {
                let url = self.assetWriter?.outputURL
                self.saveToPhotos(url: url)
                DispatchQueue.main.async {
                    completion(url)
                }
            }
        }
    }
    
    private func saveToPhotos(url: URL?) {
        guard let url = url else { return }
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    if success {
                        print("Saved to Photos!")
                    } else {
                        print("Error saving to Photos: \(String(describing: error))")
                    }
                }
            }
        }
    }
}
