//
//  DefyApp.swift
//  Defy
//
//  Created by Tanner Fause on 20.05.2026.
//

import SwiftUI

@main
struct DefyApp: App {
    @StateObject private var store = DefyStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
