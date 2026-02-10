//
//  GestureFlowApp.swift
//  GestureFlow
//
//  Created by aristides lintzeris on 10/2/2026.
//

import SwiftUI

@main
struct GestureFlowApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(coordinator)
        }
    }
}
