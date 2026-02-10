import SwiftUI

struct ActiveSessionView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        ZStack {
            // Layer 0: Camera Background
            if coordinator.cameraManager.permissionGranted {
                CameraPreviewView(cameraManager: coordinator.cameraManager)
                    .ignoresSafeArea()

                // Layer 1: Gesture Overlay
                GestureCanvasView()
                    .environmentObject(coordinator.visionEngine)

                // Layer 2: HUD / UI
                uiOverlay
                
                if coordinator.showInstructions {
                    InstructionalOverlayView()
                }
            } else {
                PermissionDeniedView()
            }
        }
    }
    
    private var uiOverlay: some View {
        VStack {
            // HUD at top
            VStack(spacing: 12) {
                // Scrolling Title
                if let title = coordinator.selectedTrackTitle {
                    ScrollingTitleView(title: title)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                
                // Centered Pitch & Speed
                HStack(spacing: 40) {
                    hudMetricView(title: "PITCH", value: String(format: "%.0f", coordinator.currentPitch), color: .green)
                    hudMetricView(title: "SPEED", value: String(format: "%.2fx", coordinator.currentSpeed), color: .green)
                }
            }
            .padding()
            .background(
                LinearGradient(gradient: Gradient(colors: [.black.opacity(0.7), .clear]), startPoint: .top, endPoint: .bottom)
            )

            Spacer()

            // Play/Pause
            Button(action: coordinator.togglePlayPause) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 80, height: 80)
                        .shadow(radius: 10)
                    
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .padding(.bottom, 120)
        }
    }
    
    private func hudMetricView(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 32, weight: .black, design: .monospaced))
                .foregroundColor(color)
        }
    }
}

struct ScrollingTitleView: View {
    let title: String
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: scrollOffset)
                .onAppear {
                    let textWidth = title.size(withAttributes: [.font: UIFont.systemFont(ofSize: 18, weight: .bold)]).width
                    let containerWidth = geometry.size.width
                    
                    if textWidth > containerWidth {
                        withAnimation(Animation.linear(duration: Double(textWidth) / 40).repeatForever(autoreverses: false)) {
                            scrollOffset = -textWidth
                        }
                    } else {
                        scrollOffset = (containerWidth - textWidth) / 2
                    }
                }
        }
        .frame(height: 25)
    }
}
