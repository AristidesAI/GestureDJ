import SwiftUI

struct RootContainerView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        TabView(selection: $coordinator.selectedTab) {
            SettingsView()
                .tag(0)
            
            ActiveSessionView()
                .tag(1)
            
            LibraryView()
                .tag(2)
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}
