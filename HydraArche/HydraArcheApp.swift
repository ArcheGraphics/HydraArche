//
//  HydraArcheApp.swift
//  HydraArche
//
//  Created by yangfengzz on 2023/3/24.
//

import SwiftUI

@main
struct HydraArcheApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: HydraArcheDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
