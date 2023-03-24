//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

import SwiftUI

struct ContentView: View {
    let canvas: Canvas
    let renderer: AAPLRenderer
    
    init(document: String) {
        canvas = Canvas(frame: CGRect())
        renderer = AAPLRenderer(metalKitView: canvas)
        canvas.setRenderer(renderer)
        
        renderer.setupScene(document)
    }
    
    var body: some View {
        RenderView(view: canvas)
    }
}
