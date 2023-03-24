//
//  ContentView.swift
//  HydraArche
//
//  Created by yangfengzz on 2023/3/24.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: HydraArcheDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(HydraArcheDocument()))
    }
}
