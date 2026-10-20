//
//  TitleButtons.swift
//  McAmp
//
//  Created by Simone Karin Lehmann on 20.10.26.
//

import Cocoa

class TitleButtons: NSView {
    var onMenu: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onShadeChanged: ((Bool) -> Void)?
    var onClose: (() -> Void)?

    private static let buttonSize = NSSize(width: 9, height: 10)
    // coordinates as offset from right side border: logicalWidth - x
    private static let buttonXoff: [CGFloat] = [269, 30, 20, 11]
    var isShaded: Bool = false {
        didSet {
            guard isShaded != oldValue else { return }
            onShadeChanged?(isShaded)
        }
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let actions: [(() -> Void)?] = [
             onMenu,
             onMinimize,
             { [weak self] in self?.isShaded.toggle() },
             onClose
         ]
        let hitY: CGFloat = 2
        for (x, action) in zip(Self.buttonXoff, actions) {
            let rect = NSRect(origin: NSPoint(x: frame.width - x, y: hitY), size: Self.buttonSize)
            if rect.contains(point) {
                action?()
                return
            }
        }
        super.mouseDown(with: event)
    }
    
}
