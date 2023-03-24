//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

import SwiftUI

struct RenderView: NSViewRepresentable {
    typealias NSViewType = HydraArche.Canvas
    
    let view: NSViewType
    
    func makeNSView(context: Context) -> NSViewType {
        view
    }
    
    func updateNSView(_ nsView: NSViewType, context: Context) {
    }
}
