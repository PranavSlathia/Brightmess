import AppKit

/// The firefly is an original-colour image: never tint it with the system template colour.
/// The small badges change shape as well as colour; neither schedules idle redraws.
@MainActor enum DeskMark {
    enum Mode: CaseIterable, Hashable {
        case linked, solar, attention
        var label: String {
            switch self {
            case .linked: return "BRIGHTMESS: open Source Deck"
            case .solar: return "BRIGHTMESS: solar fallback"
            case .attention: return "BRIGHTMESS: receiver needs attention"
            }
        }
    }

    static let size = NSSize(width: 23, height: 17)
    private static let artwork: NSImage? = {
        // The installed app has a flat resource; swift run and panel-preview use
        // the SwiftPM bundle next to the executable. A standalone CLI has neither.
        var bundles = [Bundle.main]
        if let parent = Bundle.main.executableURL?.deletingLastPathComponent(),
           let package = Bundle(url: parent.appendingPathComponent("BrightnessRelay_BrightnessRelay.bundle")) {
            bundles.append(package)
        }
        for bundle in bundles {
            if let url = bundle.url(forResource: "FireflyMenu", withExtension: "png"),
               let image = NSImage(contentsOf: url), image.isValid { return image }
        }
        return nil
    }()
    private static var cache = [Mode:NSImage]()
    private static let ink = NSColor(srgbRed:0.055, green:0.17, blue:0.14, alpha:1)
    private static let pear = NSColor(srgbRed:0.74, green:0.92, blue:0.32, alpha:1)
    private static let amber = NSColor(srgbRed:1, green:0.70, blue:0.20, alpha:1)

    static func image(_ mode: Mode) -> NSImage {
        if let image = cache[mode] { return image }
        let asset = artwork, outline = ink
        let image = NSImage(size:size, flipped:true) { _ in
            if let asset {
                let fit = min(22/asset.size.width, 17/asset.size.height)
                let w = asset.size.width*fit, h = asset.size.height*fit
                let rect = NSRect(x:(size.width-w)/2, y:(size.height-h)/2, width:w, height:h)
                NSGraphicsContext.current?.imageInterpolation = .high
                asset.draw(in:rect, from:.zero, operation:.sourceOver, fraction:1,
                           respectFlipped:true, hints:nil)
            } else {
                // A loose CLI launched as a menu app still has a coloured mark.
                func bead(_ rect: NSRect, _ fill: NSColor) {
                    let path = NSBezierPath(ovalIn:rect); fill.setFill(); path.fill()
                    outline.setStroke(); path.lineWidth = 0.7; path.stroke()
                }
                bead(NSRect(x:1,y:5,width:12,height:7),.systemTeal)
                bead(NSRect(x:13,y:1,width:7,height:12),pear)
                bead(NSRect(x:9,y:10,width:7,height:6),amber)
                bead(NSRect(x:9,y:6,width:6,height:5),ink)
            }
            drawBadge(mode)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = mode.label
        cache[mode] = image
        return image
    }

    private static func drawBadge(_ mode: Mode) {
        guard mode != .linked else { return }
        let badge = NSBezierPath()
        if mode == .solar {
            badge.appendOval(in:NSRect(x:15.5,y:9.3,width:7,height:7))
        } else {
            badge.move(to:NSPoint(x:19,y:8.3)); badge.line(to:NSPoint(x:22.7,y:15.7))
            badge.line(to:NSPoint(x:15.3,y:15.7)); badge.close()
        }
        (mode == .solar ? amber : NSColor(srgbRed:1,green:0.54,blue:0.35,alpha:1)).setFill()
        badge.fill(); ink.setStroke(); badge.lineWidth = 0.85; badge.stroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.0; glyph.lineCapStyle = .round
        if mode == .solar {
            glyph.appendArc(withCenter:NSPoint(x:19,y:13.7),radius:1.7,startAngle:180,endAngle:360)
            glyph.move(to:NSPoint(x:16.8,y:13.8)); glyph.line(to:NSPoint(x:21.2,y:13.8))
        } else {
            glyph.move(to:NSPoint(x:19,y:10.8)); glyph.line(to:NSPoint(x:19,y:12.7))
            ink.setFill(); NSBezierPath(ovalIn:NSRect(x:18.45,y:13.55,width:1.1,height:1.1)).fill()
        }
        glyph.stroke()
    }
}
