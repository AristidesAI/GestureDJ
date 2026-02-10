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
                    instructionalOverlay
                }
                
                // Layer 3: Launch Intro
                if showSplash {
                    splashOverlay
                }
            } else {
                PermissionDeniedView()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 1.0)) {
                    showSplash = false
                }
            }
        }
    }
    
    @State private var showSplash = true
    
    private var splashOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Note: Using the Default icon from assets
            VStack(spacing: 32) {
                Image("Untitled-iOS-Default-1024x1024@1x")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 140, height: 140)
                    .cornerRadius(28)
                    .shadow(color: .green.opacity(0.3), radius: 20, x: 0, y: 0)
                
                ProgressView()
                    .tint(.green)
                    .scaleEffect(1.5)
            }
        }
        .transition(.opacity)
        .zIndex(100)
    }
    
    private var uiOverlay: some View {
        ZStack {
            portraitLayout
            
            // Global Recording Indicator
            if coordinator.recordManager.isRecording {
                recordingIndicator
                    .padding(.trailing, 20)
                    .padding(.top, 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
    }
    
    // MARK: - Portrait Layout
    private var portraitLayout: some View {
        VStack {
            // HUD at top
            hudHeader
                .background(
                    LinearGradient(gradient: Gradient(colors: [.black.opacity(0.7), .clear]), startPoint: .top, endPoint: .bottom)
                )

            Spacer()

            // Controls at bottom
            HStack(spacing: 20) {
                secondaryControlButton(icon: "arrow.counterclockwise", label: "RESTART", action: coordinator.restartTrack)
                
                mainPlayButton
                
                secondaryControlButton(icon: "equal.circle", label: "REBALANCE", action: coordinator.rebalanceControls)
                
                secondaryControlButton(icon: "record.circle", iconColor: .red, label: "RECORD", action: coordinator.toggleRecording)
            }
            .padding(.bottom, 60)
        }
    }
    
    
    // MARK: - Overlay Components
    
    private var instructionalOverlay: some View {
        VStack(spacing: 30) {
            Text("Open both hands to begin")
                .font(.headline)
                .foregroundColor(.white)
                .padding(.top, 100)
            
            HStack(spacing: 80) {
                VStack(spacing: 15) {
                    Image(systemName: "hand.palm.facing.me.fill")
                        .font(.system(size: 80))
                    Text("PITCH")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                    Text("UP / DOWN")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                VStack(spacing: 15) {
                    Image(systemName: "hand.palm.facing.me.fill")
                        .font(.system(size: 80))
                        .scaleEffect(x: -1, y: 1)
                    Text("SPEED")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                    Text("+ / -")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .foregroundColor(.white.opacity(0.8))
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.6).ignoresSafeArea())
        .transition(.opacity.combined(with: .scale(scale: 1.1)))
    }
    
    // MARK: - UI Components
    
    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(coordinator.recordManager.recordedDuration.truncatingRemainder(dividingBy: 2) < 1 ? 1 : 0.3)
            
            Text(timeString(from: coordinator.recordManager.recordedDuration))
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
        .cornerRadius(20)
    }
    
    private func timeString(from duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var hudHeader: some View {
        ZStack {
            // Background Layer for Title (Centered)
            if let title = coordinator.selectedTrackTitle {
                ScrollingTitleView(title: title)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 100) // Keep away from indicators and red dot
                    .opacity(0.6)
            }
            
            // Foreground Layer (Fixed Elements)
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .opacity(coordinator.recordManager.recordedDuration.truncatingRemainder(dividingBy: 2) < 1 ? 1 : 0.3)
                
                Spacer()
                
                HStack(spacing: 12) {
                    hudMetricView(title: "PITCH", value: String(format: "%.0f", coordinator.currentPitch), color: .green)
                    hudMetricView(title: "SPEED", value: String(format: "%.2fx", coordinator.currentSpeed), color: .green)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private var mainPlayButton: some View {
        Button(action: coordinator.togglePlayPause) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 80, height: 80)
                    .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.black)
            }
        }
    }
    
    private func secondaryControlButton(icon: String, iconColor: Color = .white, label: String? = nil, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 3)
                    
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(iconColor)
                }
            }
            
            if let label = label, coordinator.showInstructions {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func hudMetricView(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
            Text(value)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundColor(color)
                .shadow(color: color.opacity(0.7), radius: 15, x: 0, y: 0) // Stronger glow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                // Background shading with glow
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.6))
                
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.4), radius: 5, x: 0, y: 4)
        )
    }
    
    // MARK: - Instruction Guide
    
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
