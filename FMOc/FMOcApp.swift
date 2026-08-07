//
//  FMOcApp.swift
//  FMOc
//
//  Created by 李永升 on 2026/8/3.
//

import SwiftUI
import SwiftData

@main
struct FMOcApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(models: AppComposition.makeModels())
        }
        .modelContainer(for: [
            FavoriteCallsign.self,
            FavoriteServer.self,
            APRSMessageRecord.self,
        ])
    }
}
