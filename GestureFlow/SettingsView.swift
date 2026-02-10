import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
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
                
                Spacer()
                
                Text("Version 1.0.0")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
            .padding(.top, 50)
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
