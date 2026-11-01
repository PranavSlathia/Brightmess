import SwiftUI
import BrightnessHardware

enum DeskPaint {
    static let ink = Color(red: 0.075, green: 0.15, blue: 0.17)
    static let spruce = Color(red: 0.12, green: 0.29, blue: 0.30)
    static let mint = Color(red: 0.69, green: 0.88, blue: 0.75)
    static let gold = Color(red: 0.99, green: 0.78, blue: 0.38)
    static let coral = Color(red: 0.97, green: 0.55, blue: 0.42)
    static let cream = Color(red: 0.98, green: 0.95, blue: 0.84)
    static func paper(_ dark: Bool) -> Color { dark ? ink : Color(red: 0.97, green: 0.96, blue: 0.92) }
    static func surface(_ dark: Bool) -> Color { dark ? Color(red: 0.115, green: 0.205, blue: 0.215) : Color(red: 0.995, green: 0.99, blue: 0.96) }
}

/// Screen-printed landscape drawn in points, never sampled from the user's screen.
/// The room and chassis stay fixed. Only the picture responds to the applied level.
struct DeskDeviceArt: View {
    let kind: DeskDisplayShape
    let brightness: UInt16?
    let connected: Bool

    var body: some View {
        Canvas { ctx, size in
            let width: CGFloat = 168, height: CGFloat = 128
            let scale = min(size.width / width, size.height / height)
            ctx.translateBy(x: (size.width - width*scale)/2, y: (size.height - height*scale)/2)
            ctx.scaleBy(x: scale, y: scale)
            func rect(_ r: CGRect, _ c: Color, radius: CGFloat = 0) {
                ctx.fill(Path(roundedRect: r, cornerRadius: radius), with: .color(c))
            }
            func oval(_ r: CGRect, _ c: Color) {
                ctx.fill(Path(ellipseIn: r), with: .color(c))
            }
            func line(_ a: CGPoint, _ b: CGPoint, _ c: Color, _ w: CGFloat = 1) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            func poly(_ points: [CGPoint], _ c: Color) {
                var p = Path(); p.addLines(points); p.closeSubpath(); ctx.fill(p, with: .color(c))
            }
            let tv = kind == .television
            let field = tv ? Color(red: 0.77, green: 0.86, blue: 0.78) : Color(red: 0.98, green: 0.81, blue: 0.57)
            rect(CGRect(x: 0,y: 0,width: width,height: height), field)
            // A printed disc, a horizon and fine registration marks give each
            // tile a little depth without any idle animation or raster assets.
            oval(CGRect(x: tv ? -23 : 94,y: -34,width: 100,height: 100), (tv ? DeskPaint.mint : DeskPaint.coral).opacity(0.85))
            for i in 0..<8 {
                let x = CGFloat(i) * 5
                line(CGPoint(x: x+1,y: 90), CGPoint(x: x+20,y: 71), DeskPaint.ink.opacity(0.11))
            }
            rect(CGRect(x: 0,y: 105,width: width,height: 23), DeskPaint.ink.opacity(0.09))
            line(CGPoint(x: 0,y: 105), CGPoint(x: width,y: 105), DeskPaint.ink.opacity(0.32))
            oval(CGRect(x: 18,y: 112,width: 132,height: 7), DeskPaint.ink.opacity(0.16))
            let box: CGRect
            switch kind {
            case .portraitMonitor: box = CGRect(x: 55,y: 9,width: 55,height: 91)
            case .monitor: box = CGRect(x: 18,y: 21,width: 132,height: 74)
            case .television: box = CGRect(x: 10,y: 19,width: 148,height: 84)
            }
            if tv {
                for (x,dx) in [(box.minX+24,-7.0), (box.maxX-24,7.0)] {
                    line(CGPoint(x: x,y: box.maxY-1), CGPoint(x: x+dx,y: 114), DeskPaint.ink, 4)
                }
            } else {
                let cx = box.midX
                rect(CGRect(x: cx-3.6,y: box.maxY-1,width: 7.2,height: 113-box.maxY), DeskPaint.ink)
                poly([.init(x: cx-15,y: 111), .init(x: cx+15,y: 111),
                      .init(x: cx+20,y: 115), .init(x: cx-20,y: 115)], DeskPaint.ink)
            }
            rect(box, DeskPaint.ink, radius: 4)
            let screen = box.insetBy(dx: 3.3, dy: 3.5)
            var pic = ctx
            pic.clip(to: Path(roundedRect: screen, cornerRadius: 1.2))
            let unknown = brightness == nil
            if connected && !unknown {
                let sky = tv ? Color(red: 0.33,green: 0.59,blue: 0.66) : DeskPaint.coral
                pic.fill(Path(screen), with: .linearGradient(Gradient(colors: [sky, tv ? DeskPaint.mint : DeskPaint.gold]),
                         startPoint: CGPoint(x: 0,y: screen.minY), endPoint: CGPoint(x: 0,y: screen.maxY)))
                let sun = min(screen.width * 0.48, screen.height * 0.51)
                pic.fill(Path(ellipseIn: CGRect(x: screen.minX + screen.width*0.15, y: screen.minY + screen.height*0.12,
                                                width: sun, height: sun)), with: .color(DeskPaint.cream))
                for row in 0..<3 {
                    let y = screen.minY + screen.height * (0.56 + CGFloat(row)*0.13)
                    var p = Path(); p.move(to: CGPoint(x: screen.minX-2,y: y))
                    p.addQuadCurve(to: CGPoint(x: screen.midX,y: y+4),
                                   control: CGPoint(x: screen.minX + screen.width*0.3,y: y-17+CGFloat(row)*4))
                    p.addQuadCurve(to: CGPoint(x: screen.maxX+2,y: y-6),
                                   control: CGPoint(x: screen.minX+screen.width*0.75,y: y+17))
                    p.addLine(to: CGPoint(x: screen.maxX+2,y: screen.maxY+1))
                    p.addLine(to: CGPoint(x: screen.minX-2,y: screen.maxY+1)); p.closeSubpath()
                    pic.fill(p, with: .color([tv ? DeskPaint.spruce : Color(red: 0.71,green: 0.33,blue: 0.27),
                                               tv ? Color(red: 0.14,green: 0.39,blue: 0.39) : Color(red: 0.48,green: 0.24,blue: 0.23),
                                               DeskPaint.ink][row]))
                }
                let darkness = 0.86 * (1.0 - Double(brightness ?? 0)/100)
                pic.fill(Path(screen), with: .color(DeskPaint.ink.opacity(darkness)))
            } else {
                pic.fill(Path(screen), with: .color(DeskPaint.spruce))
                line(.init(x: screen.midX-6,y: screen.midY),.init(x: screen.midX+6,y: screen.midY),
                     DeskPaint.cream.opacity(0.7), 1.8)
            }
        }
        .aspectRatio(168.0/128.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Static horizon print behind the source header. No TimelineView, timers or
/// continuously running render loop.
struct DeskHorizon: View {
    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width-29,y: size.height*0.42), r = size.height*0.59
            ctx.fill(Path(ellipseIn: CGRect(x: center.x-r,y: center.y-r,width: 2*r,height: 2*r)),
                     with: .color(DeskPaint.gold))
            for i in 0..<6 {
                let d = CGFloat(i)*7
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x-r-d,y: center.y-r-d,width: 2*(r+d),height: 2*(r+d))),
                           with: .color(DeskPaint.mint.opacity(0.32)), lineWidth: 0.8)
            }
            for i in 0..<7 {
                let y = size.height*0.55 + CGFloat(i)*5.3
                var p = Path(); p.move(to: CGPoint(x: size.width-145,y: y+12))
                p.addQuadCurve(to: CGPoint(x: size.width+2,y: y), control: CGPoint(x: size.width-55,y: y-12))
                ctx.stroke(p, with: .color(DeskPaint.ink), lineWidth: CGFloat(i)*0.72+1.6)
            }
        }
        .clipped().accessibilityHidden(true).allowsHitTesting(false)
    }
}
