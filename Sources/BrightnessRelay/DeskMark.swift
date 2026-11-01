import AppKit

/// One vector template at menu-bar scale. The asymmetrical screens identify
/// the app; the small sky motif conveys normal, fallback, or attention state.
@MainActor enum DeskMark {
    enum Mode: CaseIterable { case linked, solar, attention }
    private static let images = Dictionary(uniqueKeysWithValues: Mode.allCases.map { ($0, draw($0)) })

    static func image(_ mode: Mode) -> NSImage { images[mode]! }

    private static func draw(_ mode: Mode) -> NSImage {
        let image = NSImage(size: NSSize(width: 23, height: 17), flipped: true) { _ in
            NSColor.black.setStroke(); NSColor.black.setFill()
            func line(_ a: NSPoint, _ b: NSPoint, _ width: CGFloat = 1.45) {
                let p = NSBezierPath(); p.lineWidth = width; p.lineCapStyle = .round
                p.move(to: a); p.line(to: b); p.stroke()
            }
            func panel(_ rect: NSRect) {
                let p = NSBezierPath(roundedRect: rect, xRadius: 1.05, yRadius: 1.05)
                p.lineWidth = 1.55; p.stroke()
            }
            panel(NSRect(x: 1.3, y: 2.8, width: 6.5, height: 10.3))
            line(.init(x: 4.55,y: 13.5), .init(x: 4.55,y: 15.5))
            line(.init(x: 2.65,y: 15.55), .init(x: 6.45,y: 15.55))
            panel(NSRect(x: 10, y: 6.0, width: 11.6, height: 7.3))
            line(.init(x: 12.8,y: 13.6), .init(x: 11.8,y: 15.1))
            line(.init(x: 18.8,y: 13.6), .init(x: 19.8,y: 15.1))
            switch mode {
            case .linked:
                line(.init(x: 10.7,y: 2), .init(x: 12.1,y: 3.5), 1.2)
                line(.init(x: 15.9,y: 0.9), .init(x: 15.9,y: 2.9), 1.3)
                line(.init(x: 21,y: 2), .init(x: 19.6,y: 3.5), 1.2)
            case .solar:
                let p = NSBezierPath(); p.appendArc(withCenter: .init(x: 15.8,y: 4.2), radius: 2.45,
                                                     startAngle: 180, endAngle: 360)
                p.lineWidth = 1.35; p.stroke()
            case .attention:
                line(.init(x: 15.8,y: 0.6), .init(x: 15.8,y: 2.1), 1.6)
                NSBezierPath(ovalIn: NSRect(x: 15.05,y: 3.05,width: 1.5,height: 1.5)).fill()
            }
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "Brightness Relay"
        return image
    }
}
