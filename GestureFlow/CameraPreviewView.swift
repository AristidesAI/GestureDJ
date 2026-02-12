import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.videoPreviewLayer.session = cameraManager.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        
        // Mirror for front camera
        if view.videoPreviewLayer.connection?.isVideoMirroringSupported == true {
            view.videoPreviewLayer.connection?.automaticallyAdjustsVideoMirroring = false
            view.videoPreviewLayer.connection?.isVideoMirrored = true
        }
        
        return view
    }
    
    func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        // Update session if it changed
        if uiView.videoPreviewLayer.session != cameraManager.session {
            uiView.videoPreviewLayer.session = cameraManager.session
        }

        // Update orientation
        if let connection = uiView.videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            let deviceOrientation = UIDevice.current.orientation
            let videoOrientation: AVCaptureVideoOrientation

            switch deviceOrientation {
            case .landscapeLeft: videoOrientation = .landscapeRight
            case .landscapeRight: videoOrientation = .landscapeLeft
            case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
            default: videoOrientation = .portrait
            }

            if connection.videoOrientation != videoOrientation {
                connection.videoOrientation = videoOrientation
            }
        }
    }
}

class VideoPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
