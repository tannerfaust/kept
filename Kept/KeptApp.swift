//
//  KeptApp.swift
//  Kept
//
//  Created by Tanner Fause on 20.05.2026.
//

import SwiftUI

@main
struct KeptApp: App {
    @StateObject private var store = KeptStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
