import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: AppCoordinator // Now finds AppCoordinator
    
    var body: some View {
        CameraView() // Now finds CameraView
            .sheet(isPresented: $coordinator.isShowingLibrary) {
                LibraryView() // Now finds LibraryView
            }
    }
}
