//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

import SwiftUI

struct ContentView: View {
    @Binding var document: HydraArcheDocument

    let canvas: Canvas
    let renderer: AAPLRenderer
    
    init(document: Binding<HydraArcheDocument>) {
        _document = document
        canvas = Canvas(frame: CGRect())
        renderer = AAPLRenderer(metalKitView: canvas)
        canvas.setRenderer(renderer)
    }
    
    var body: some View {
        RenderView(view: canvas)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(document: .constant(HydraArcheDocument()))
    }
}
