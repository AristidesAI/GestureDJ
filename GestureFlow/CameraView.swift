import SwiftUI

struct CameraView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            // --- FIX: Conditionally show camera or permission message ---
            if coordinator.cameraManager.permissionGranted {
                // We have permission, show the camera and UI
                CameraPreviewView(cameraManager: coordinator.cameraManager)
                    .ignoresSafeArea()

                GestureCanvasView()
                    .environmentObject(coordinator.visionEngine)

                // Main UI overlay
                uiOverlay
                
                if coordinator.showInstructions {
                    InstructionalOverlayView()
                }

            } else {
                // No permission, show a helpful view
                PermissionDeniedView()
            }
        }
        // --- FIX: Request permission when the view appears on screen ---
        .onAppear {
            coordinator.cameraManager.requestPermission()
        }
    }
    
    // Extracted the UI into a computed property for cleanliness
    private var uiOverlay: some View {
        VStack {
            HStack {
                Button(action: coordinator.openLibrary) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                Spacer()
                
                if let title = coordinator.selectedTrackTitle {
                    VStack(alignment: .trailing) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(15)
                        Text("Change")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            Button(action: coordinator.togglePlayPause) {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .foregroundColor(.black)
                    .padding(25)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .scaleEffect(1.2)
                            .opacity(0.5)
                    )
            }
            .padding(.bottom, 40)
        }
    }
}


// --- FIX: A new helper view for when camera access is denied ---
struct PermissionDeniedView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                
                Text("Camera Access Required")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("To control music with gestures, please grant camera access in your device settings.")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Button to open the app's settings directly
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
    }
}


// (InstructionalOverlayView remains the same as before)
struct InstructionalOverlayView: View {
    var body: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .overlay(
                VStack(spacing: 20) {
                    Text("Position Your Hands")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 40) {
                        Image(systemName: "hand.palm.facing.me.fill")
                        Image(systemName: "hand.palm.facing.me.fill")
                            .scaleEffect(x: -1, y: 1) // Mirror the second hand
                    }
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    
                    Text("Place both hands in the frame to begin playback.")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            )
    }
}
