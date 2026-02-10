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
        // Update session if it changed (though it's persistent in CameraManager)
        if uiView.videoPreviewLayer.session != cameraManager.session {
            uiView.videoPreviewLayer.session = cameraManager.session
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
