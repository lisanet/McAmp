import Cocoa

// One independent NSWindow per Winamp panel. Parent links form a tree rooted at MAIN.
enum DockWindowID: CaseIterable, Hashable {
    case main, equalizer, playlist
}

private final class DockPreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        bounds.fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        outline.lineWidth = 3
        outline.stroke()
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

final class WindowDockingController {
    private struct SnapCandidate {
        let member: DockWindowID
        let target: DockWindowID
        let delta: NSPoint
        let distance: CGFloat
    }

    private let snapDistance: CGFloat = 50
    private var windows: [DockWindowID: NSWindow] = [:]
    private var parent: [DockWindowID: DockWindowID] = [:]
    private var draggedID: DockWindowID?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrames: [DockWindowID: NSRect] = [:]
    private var draggedGroup = Set<DockWindowID>()
    private var previews: [DockWindowID: DockPreviewWindow] = [:]
    private var currentSnap: SnapCandidate?
    private var mainMoveObserver: NSObjectProtocol?
    private var lastMainOrigin: NSPoint = .zero
    private var movingGroupInternally = false

    deinit {
        if let mainMoveObserver { NotificationCenter.default.removeObserver(mainMoveObserver) }
    }

    func register(_ window: NSWindow, as id: DockWindowID) {
        windows[id] = window
        if id == .main {
            lastMainOrigin = window.frame.origin
            mainMoveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main
            ) { [weak self] _ in self?.mainWindowMoved() }
        }
    }

    // Initial docking, or explicit layout reset. Descendants follow their parent.
    func dock(_ child: DockWindowID, to target: DockWindowID) {
        guard child != .main, child != target,
              !descendants(of: child).contains(target),
              let childWindow = windows[child], let targetWindow = windows[target] else { return }
        let previous = childWindow.frame.origin
        let newOrigin = NSPoint(x: targetWindow.frame.minX,
                                y: targetWindow.frame.minY - childWindow.frame.height)
        parent[child] = target
        childWindow.setFrameOrigin(newOrigin)
        moveDockedChildren(of: child, by: NSPoint(x: newOrigin.x - previous.x,
                                                   y: newOrigin.y - previous.y))
    }

    func beginDragging(_ id: DockWindowID, mouseLocation: NSPoint) {
        guard draggedID == nil, windows[id] != nil else { return }
        draggedID = id
        dragStartMouse = mouseLocation
        draggedGroup = descendants(of: id).union([id])
        dragStartFrames = Dictionary(uniqueKeysWithValues: draggedGroup.compactMap { member in
            windows[member].map { (member, $0.frame) }
        })
        currentSnap = nil

        // Main player drags the REAL windows, live. No outline.
        if id == .main { return }

        // A dragged EQ+playlist group needs an outline for BOTH windows.
        for member in draggedGroup {
            guard let frame = dragStartFrames[member] else { continue }
            let preview = DockPreviewWindow(frame: frame)
            preview.level = windows[member]?.level ?? .normal
            preview.orderFront(nil)
            previews[member] = preview
        }
    }

    func updateDragging(mouseLocation: NSPoint) {
        guard let id = draggedID else { return }
        let rawDelta = NSPoint(x: mouseLocation.x - dragStartMouse.x,
                               y: mouseLocation.y - dragStartMouse.y)

        if id == .main {
            // Main moves normally; all docked windows follow visibly.
            applyDelta(rawDelta)
            return
        }

        currentSnap = bestSnap(rawDelta: rawDelta)
        let delta = currentSnap?.delta ?? rawDelta
        for member in draggedGroup {
            guard let start = dragStartFrames[member] else { continue }
            previews[member]?.setFrameOrigin(NSPoint(x: start.minX + delta.x,
                                                      y: start.minY + delta.y))
        }
    }

    func endDragging(mouseLocation: NSPoint) {
        guard let id = draggedID else { return }
        updateDragging(mouseLocation: mouseLocation)
        if id == .main {
            cleanupDrag()
            return
        }

        if let snap = currentSnap {
            // Only commit a new parent after a valid snap. No free floating panels.
            parent[snap.member] = snap.target
            applyDelta(snap.delta)
        }
        // No candidate: original frames and parent links remain untouched.
        cleanupDrag()
    }

    func moveDockedChildren(of id: DockWindowID, by delta: NSPoint) {
        for member in descendants(of: id) {
            guard let window = windows[member] else { continue }
            window.setFrameOrigin(NSPoint(x: window.frame.minX + delta.x,
                                          y: window.frame.minY + delta.y))
        }
    }

    private func applyDelta(_ delta: NSPoint) {
        movingGroupInternally = true
        defer {
            movingGroupInternally = false
            if let main = windows[.main] { lastMainOrigin = main.frame.origin }
        }
        for member in draggedGroup {
            guard let start = dragStartFrames[member], let window = windows[member] else { continue }
            window.setFrameOrigin(NSPoint(x: start.minX + delta.x,
                                          y: start.minY + delta.y))
        }
    }

    // Also handle AppDelegate / macOS moving the main window after initialization.
    private func mainWindowMoved() {
        guard !movingGroupInternally, let main = windows[.main] else { return }
        let now = main.frame.origin
        let delta = NSPoint(x: now.x - lastMainOrigin.x, y: now.y - lastMainOrigin.y)
        lastMainOrigin = now
        if delta.x != 0 || delta.y != 0 { moveDockedChildren(of: .main, by: delta) }
    }

    private func bestSnap(rawDelta: NSPoint) -> SnapCandidate? {
        var candidates: [SnapCandidate] = []
        // Any panel in the dragged group may touch an external window.
        for member in draggedGroup where member == draggedID {
            guard let start = dragStartFrames[member] else { continue }
            let moving = start.offsetBy(dx: rawDelta.x, dy: rawDelta.y)
            for targetID in DockWindowID.allCases where !draggedGroup.contains(targetID) {
                guard let targetWindow = windows[targetID], targetWindow.isVisible else { continue }
                let target = targetWindow.frame
                let origins = [
                    // Below and above: left edges coincide.
                    NSPoint(x: target.minX, y: target.minY - moving.height),
                    NSPoint(x: target.minX, y: target.maxY),
                    // Right and left: TOP edges coincide.
                    NSPoint(x: target.maxX, y: target.maxY - moving.height),
                    NSPoint(x: target.minX - moving.width, y: target.maxY - moving.height)
                ]
                for origin in origins {
                    let distance = hypot(moving.minX - origin.x, moving.minY - origin.y)
                    guard distance <= snapDistance else { continue }
                    let delta = NSPoint(x: rawDelta.x + origin.x - moving.minX,
                                        y: rawDelta.y + origin.y - moving.minY)
                    candidates.append(SnapCandidate(member: member, target: targetID,
                                                     delta: delta, distance: distance))
                }
            }
        }
        return candidates.min { $0.distance < $1.distance }
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
        for preview in previews.values { preview.orderOut(nil) }
        previews.removeAll()
        draggedID = nil
        draggedGroup.removeAll()
        dragStartFrames.removeAll()
        currentSnap = nil
    }
}
