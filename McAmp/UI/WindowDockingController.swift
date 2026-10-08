import Cocoa

enum DockWindowID: CaseIterable, Hashable {
    case main
    case equalizer
    case playlist
}

private final class DockPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        bounds.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.stroke()
    }
}

private final class DockPreviewWindow: NSWindow {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = DockPreviewView(frame: NSRect(origin: .zero, size: frame.size))
    }
}

/// Coordinates Winamp-style dragging and docking for the three independent windows.
/// A dock relation means "child follows parent". Relations may form a chain, e.g.
/// main -> equalizer -> playlist.
final class WindowDockingController {
    private struct SnapCandidate {
        let target: DockWindowID
        let origin: NSPoint
        let distance: CGFloat
    }

    private let snapDistance: CGFloat = 50
    private var windows: [DockWindowID: NSWindow] = [:]
    private var parent: [DockWindowID: DockWindowID] = [:]

    private var draggedID: DockWindowID?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrames: [DockWindowID: NSRect] = [:]
    private var draggedGroup: Set<DockWindowID> = []
    private var previewWindow: DockPreviewWindow?
    private var currentSnap: SnapCandidate?

    func register(_ window: NSWindow, as id: DockWindowID) {
        windows[id] = window
    }

    func dock(_ child: DockWindowID, to target: DockWindowID) {
        guard child != target, !descendants(of: child).contains(target) else { return }
        parent[child] = target
        guard let childWindow = windows[child], let targetWindow = windows[target] else { return }
        childWindow.setFrameOrigin(originDirectlyBelow(child: childWindow.frame, target: targetWindow.frame))
    }

    func undock(_ id: DockWindowID) {
        parent[id] = nil
    }

    func beginDragging(_ id: DockWindowID, mouseLocation: NSPoint) {
        guard let window = windows[id] else { return }
        draggedID = id
        dragStartMouse = mouseLocation

        // Picking up a child detaches it from its old parent. Its own children remain attached.
        parent[id] = nil
        draggedGroup = descendants(of: id).union([id])
        dragStartFrames = Dictionary(uniqueKeysWithValues: draggedGroup.compactMap { child in
            windows[child].map { (child, $0.frame) }
        })

        let preview = DockPreviewWindow(frame: window.frame)
        preview.orderFront(nil)
        previewWindow = preview
        window.alphaValue = 0.82
    }

    func updateDragging(mouseLocation: NSPoint) {
        guard let id = draggedID, let start = dragStartFrames[id] else { return }
        let delta = NSPoint(x: mouseLocation.x - dragStartMouse.x,
                            y: mouseLocation.y - dragStartMouse.y)
        let proposed = NSRect(x: start.origin.x + delta.x,
                              y: start.origin.y + delta.y,
                              width: start.width,
                              height: start.height)

        currentSnap = bestSnap(for: id, proposedFrame: proposed)
        let previewOrigin = currentSnap?.origin ?? proposed.origin
        previewWindow?.setFrameOrigin(previewOrigin)
    }

    func endDragging(mouseLocation: NSPoint) {
        guard let id = draggedID, let start = dragStartFrames[id] else { cleanupDrag(); return }
        updateDragging(mouseLocation: mouseLocation)

        let delta: NSPoint
        if let snap = currentSnap {
            delta = NSPoint(x: snap.origin.x - start.origin.x, y: snap.origin.y - start.origin.y)
            parent[id] = snap.target
        } else {
            delta = NSPoint(x: mouseLocation.x - dragStartMouse.x,
                            y: mouseLocation.y - dragStartMouse.y)
        }

        // Move the selected window and every window docked below it by the same delta.
        for member in draggedGroup {
            guard let initial = dragStartFrames[member], let window = windows[member] else { continue }
            window.setFrameOrigin(NSPoint(x: initial.origin.x + delta.x,
                                          y: initial.origin.y + delta.y))
        }
        cleanupDrag()
    }

    func moveDockedChildren(of id: DockWindowID, by delta: NSPoint) {
        for child in descendants(of: id) {
            guard let window = windows[child] else { continue }
            window.setFrameOrigin(NSPoint(x: window.frame.origin.x + delta.x,
                                          y: window.frame.origin.y + delta.y))
        }
    }

    private func bestSnap(for movingID: DockWindowID, proposedFrame: NSRect) -> SnapCandidate? {
        var candidates: [SnapCandidate] = []
        for targetID in DockWindowID.allCases where targetID != movingID && !draggedGroup.contains(targetID) {
            guard let targetWindow = windows[targetID], targetWindow.isVisible else { continue }
            let target = targetWindow.frame

            // Primary Winamp arrangement: moving window immediately below target,
            // with exactly the same left edge.
            let below = originDirectlyBelow(child: proposedFrame, target: target)
            let belowDistance = hypot(proposedFrame.minX - below.x, proposedFrame.maxY - target.minY)
            if belowDistance <= snapDistance {
                candidates.append(SnapCandidate(target: targetID, origin: below, distance: belowDistance))
            }

            // Also allow docking immediately above another window. The moved window's
            // left edge is still aligned exactly to the target's left edge.
            let above = NSPoint(x: target.minX, y: target.maxY)
            let aboveDistance = hypot(proposedFrame.minX - above.x, proposedFrame.minY - target.maxY)
            if aboveDistance <= snapDistance {
                candidates.append(SnapCandidate(target: targetID, origin: above, distance: aboveDistance))
            }
        }
        return candidates.min { $0.distance < $1.distance }
    }

    private func originDirectlyBelow(child: NSRect, target: NSRect) -> NSPoint {
        NSPoint(x: target.minX, y: target.minY - child.height)
    }

    private func descendants(of id: DockWindowID) -> Set<DockWindowID> {
        var result = Set<DockWindowID>()
        var changed = true
        while changed {
            changed = false
            for (child, p) in parent where (p == id || result.contains(p)) && !result.contains(child) {
                result.insert(child)
                changed = true
            }
        }
        return result
    }

    private func cleanupDrag() {
        if let id = draggedID { windows[id]?.alphaValue = 1.0 }
        previewWindow?.orderOut(nil)
        previewWindow = nil
        currentSnap = nil
        draggedID = nil
        draggedGroup.removeAll()
        dragStartFrames.removeAll()
    }
}
