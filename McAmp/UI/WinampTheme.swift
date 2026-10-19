import Cocoa

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

final class WinampTheme {
    // MARK: - Skin facade
    static var provider: SkinProvider!  // we always have a skin, either the default of the app bundle, or an already loaded one

    static func sprite(_ key: SpriteKey) -> NSImage? {
        provider.sprite(key)
    }

    // MARK: - Frame
    static let greenBright = NSColor(hex: 0x00E000)

    // MARK: - Scale
    static var scale: CGFloat = 1.4

    // MARK: - Dimensions
    static let windowWidth: CGFloat = 275
    static let shadedHeight: CGFloat = 14
    static let mainPlayerHeight: CGFloat = 116
    static let equalizerHeight: CGFloat = 116
    static let playlistMinHeight: CGFloat = 232
    static let titleBarHeight: CGFloat = 16
    static let transportButtonSize = NSSize(width: 22, height: 18)
    
    // MARK: - Composite Images, prerenderd, avoids scaling artifacts
    static var eqCompositeImage: NSImage?
    static var plvCompositeImage: NSImage?
    static var plvShadedImage: NSImage?
    static var scrollerCompositeImage: NSImage?
    
    static func invalidateCache() {
        eqCompositeImage = nil
        plvCompositeImage = nil
        plvShadedImage = nil
        scrollerCompositeImage = nil
    }
}
