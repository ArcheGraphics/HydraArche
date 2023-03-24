//  Copyright (c) 2023 Feng Yang
//
//  I am making my contributions/submissions to this project solely in my
//  personal capacity and am not conveying any rights to any intellectual
//  property of any third parties.

import Foundation

public class Canvas: MTKView {
    var _mouseCoord = CGPoint()
    var _renderer: AAPLRenderer!

    public init(frame frameRect: CGRect) {
        super.init(frame: frameRect, device: nil)
        layer!.backgroundColor = NSColor.clear.cgColor
    }
    
    func setRenderer(_ renderer: AAPLRenderer) {
        _renderer = renderer
        delegate = _renderer
        _renderer.mtkView(self, drawableSizeWillChange: bounds.size)
    }
    
    public required init(coder: NSCoder) {
        fatalError("unImplement")
    }

    public override func mouseDown(with event: NSEvent) {
        _mouseCoord = convert(event.locationInWindow, from: nil)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        let newCoord = convert(event.locationInWindow, from: nil)
        let dX = newCoord.x - _mouseCoord.x
        let dY = newCoord.y - _mouseCoord.y
        
        if (event.modifierFlags.contains(.option)) {
            let magnification = event.modifierFlags.contains(.shift) ? 2.0 : 0.5
            _renderer.pan(byDelta: Float(-dX * magnification), Float(-dY * magnification))
        } else {
            _renderer.rotate(byDelta: -Float(dX) * 0.5, Float(dY) * 0.5)
        }
        
        _mouseCoord = newCoord
    }
    
    public override func magnify(with event: NSEvent) {
        let delta = -event.magnification
        let magnification = event.modifierFlags.contains(.shift) ? 160.0 : 16.0
        _renderer.zoom(byDelta: Float(delta * magnification))
    }
    
    public override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let delta = 5.0 * event.deltaY
            _renderer.zoom(byDelta: Float(delta))
        } else {
            let dX = event.deltaX
            let dY = event.deltaY
            let magnification = event.modifierFlags.contains(.shift) ? 5.0 : 1.0
            _renderer.pan(byDelta: Float(-dX * magnification), Float(dY * magnification))
        }
    }
}
