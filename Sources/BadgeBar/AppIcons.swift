import AppKit

/// A small cache of monochrome status-bar images. No full-resolution app icons
/// are retained after the one-time template render.
@MainActor
enum AppIcons {
    private static let menuBarCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    static func menuBarIcon(forBundleId bundleId: String) -> NSImage {
        if let hit = menuBarCache.object(forKey: bundleId as NSString) { return hit }

        let size = NSSize(width: 18, height: 18)
        let image: NSImage

        if bundleId == "com.tinyspeck.slackmacgap",
           let symbol = NSImage(systemSymbolName: "number", accessibilityDescription: "Slack") {
            // Slack's original icon can appear as a square when templated.
            image = symbol
            image.size = size
        } else {
            let source: NSImage
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                source = NSWorkspace.shared.icon(forFile: url.path)
            } else {
                source = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
            }
            let template = NSImage(size: size)
            template.lockFocus()
            source.draw(in: NSRect(origin: .zero, size: size),
                        from: .zero, operation: .sourceOver, fraction: 1.0)
            template.unlockFocus()
            image = template
        }

        image.isTemplate = true
        menuBarCache.setObject(image, forKey: bundleId as NSString)
        return image
    }
}
