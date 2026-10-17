//
//  MiniControls.swift
//  McAmp
//
//  Created by Simone Karin Lehmann on 17.10.26.
//

import Cocoa

class MiniControls: NSView {
    var onPrevious: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onNext: (() -> Void)?
    var onEject: (() -> Void)?

    // Six baked mini-transport buttons in pledit.bmp's BR corner and in shaded main player
    // eject has a 1 px gap.
    private static let buttonSize = NSSize(width: 9, height: 11)
    private static let buttonXs: [CGFloat] = [0, 9, 18, 27, 36, 46]
        
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
    
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let actions = [onPrevious, onPlay, onPause, onStop, onNext, onEject]

        for (x, action) in zip(Self.buttonXs, actions) {
            let rect = NSRect(origin: NSPoint(x: x, y: 0), size: Self.buttonSize)
            if rect.contains(point) {
                action?()
                return
            }
        }
        super.mouseDown(with: event)
    }
    
}
