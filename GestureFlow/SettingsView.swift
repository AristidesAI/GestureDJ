import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 20) {
                        settingRow(title: "Hand Detection Sensitivity", value: coordinator.sensitivity) {
                            coordinator.cycleSensitivity()
                        }
                        settingRow(title: "Smoothing (Kalman)", value: String(format: "%.2f", coordinator.smoothing)) {
                            coordinator.cycleSmoothing()
                        }
                        settingRow(title: "No-Hands Delay", value: String(format: "%.1fs", coordinator.noHandsDelay)) {
                            coordinator.cycleNoHandsDelay()
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(15)
                    .padding(.horizontal)
                    
                    // Quick Guide Section
                    instructionalGuide
                    
                    Spacer(minLength: 20)
                    
                    Text("Version 1.0.0")
                        .foregroundColor(.gray)
                        .font(.footnote)
                }
                .padding(.top, 50)
            }
        }
    }
    
    private var instructionalGuide: some View {
        VStack(spacing: 20) {
            Text("QUICK GUIDE")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green)
                .tracking(2)
            
            VStack(alignment: .leading, spacing: 10) {
                guideRow(icon: "hand.raised.fill", text: "Hold palms towards camera, fingers spread wide for best tracking.")
                guideRow(icon: "arrow.triangle.2.circlepath", text: "Lost a hand? Simply pull it out of view and bring it back in to auto-reset your baseline.")
                guideRow(icon: "hand.draw.fill", text: "Pinch index and thumb to dynamically modulate Pitch and Speed.")
                guideRow(icon: "music.note.list", text: "Choose your own audio from your videos or files")
                guideRow(icon: "heart.fill", text: "Please enjoy this app made with Apple's Machine Vision System, Made by Aristides Lintzeris")
            }
            .padding(.horizontal)
            
            Divider().background(Color.white.opacity(0.1))
            
            // Button Legend Table
            Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 15) {
                GridRow {
                    legendItem(icon: "arrow.counterclockwise", text: "Restart Track")
                    legendItem(icon: "equal.circle", text: "Rebalance P/S")
                }
                GridRow {
                    legendItem(icon: "record.circle", text: "Record Session")
                    legendItem(icon: "play.fill", text: "Start / Pause")
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 24)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
        .padding(.horizontal)
    }
    
    private func guideRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.system(size: 16))
                .frame(width: 24)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(4)
        }
    }
    
    private func legendItem(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.15)))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private func settingRow(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.white)
                Spacer()
                Text(value)
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
            }
            .padding(.vertical, 8)
        }
    }
}
