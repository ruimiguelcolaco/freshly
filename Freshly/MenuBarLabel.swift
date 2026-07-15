import AppKit
import SwiftUI

/// The status item's label: the plain template glyph when everything is
/// fresh, and — when updates are pending — one capsule where the glyph
/// and the count live together. The capsule is rendered to an `NSImage`
/// because the menu bar flattens live SwiftUI styling.
struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count == 0 {
            Image(systemName: "arrow.triangle.2.circlepath")
        } else {
            Image(nsImage: MenuBarBadgeRenderer.image(for: count))
        }
    }
}

/// Renders and caches one badge image per pending-update count.
@MainActor
enum MenuBarBadgeRenderer {
    private static var cache: [Int: NSImage] = [:]

    static func image(for count: Int) -> NSImage {
        if let cached = cache[count] {
            return cached
        }
        let renderer = ImageRenderer(content: MenuBarBadge(count: count))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        // Colored on purpose — never let the menu bar template it away.
        image.isTemplate = false
        cache[count] = image
        return image
    }
}

/// White glyph and count on Freshly's strawberry pink — the same color
/// as the app icon's gradient, and self-contained enough to stay legible
/// on any menu bar, light or dark.
private struct MenuBarBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10, weight: .bold))
            Text(verbatim: count > 99 ? "99+" : String(count))
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.leading, 5)
        .padding(.trailing, 6)
        .frame(height: 16)
        .background(Capsule().fill(Color(.displayP3, red: 1.0, green: 0.395, blue: 0.47)))
        .padding(1)
    }
}
