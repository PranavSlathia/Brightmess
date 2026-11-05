import AppKit

/// The Brightest Mess: a crooked sun with one ray that can't stay put.
/// This is a brand mark, not a brightness reading or a solar status indicator.
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
    enum Frame: Int, CaseIterable {
        case resting = -1, start, one, two, three, four, five, six, seven, eight, nine, settled
        var sparkKick: CGFloat {
            guard self != .resting else { return 0 }
            let progress = CGFloat(rawValue) / CGFloat(Frame.settled.rawValue)
            return 10 * pow(1-progress,2)
        }
    }
    private struct Key: Hashable { let mode: Mode, frame: Frame }
    static let size = NSSize(width:23,height:17)
    private static var cache=[Key:NSImage]()

    private nonisolated static func color(_ hex:Int)->NSColor {
        NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
    }
    private static func polygon(_ points:[NSPoint])->NSBezierPath {
        let path=NSBezierPath();path.move(to:points[0])
        for point in points.dropFirst() { path.line(to:point) }
        path.close();return path
    }

    // All paths share a 100-point square, with y increasing downwards. The
    // compiler artwork and the menu mark are drawn from these same shapes.
    private static func drawSun(in rect:NSRect, kick:CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform=NSAffineTransform()
        transform.translateX(by:rect.minX,yBy:rect.minY)
        transform.scaleX(by:rect.width/100,yBy:rect.height/100)
        transform.concat()
        let forest=color(0x142E26), gold=color(0xFFD255)
        func shape(_ path:NSBezierPath, fill:NSColor) {
            fill.setFill();path.fill()
            forest.setStroke();path.lineWidth=2.3;path.lineJoinStyle = .round;path.stroke()
        }
        func ray(_ points:[NSPoint]) { shape(polygon(points),fill:gold) }
        ray([.init(x:45,y:23),.init(x:41,y:8),.init(x:59,y:4),.init(x:55,y:23)])
        ray([.init(x:12,y:29),.init(x:20,y:19),.init(x:32,y:31),.init(x:25,y:38)])
        ray([.init(x:6,y:50),.init(x:19,y:49),.init(x:19,y:57),.init(x:6,y:61)])
        ray([.init(x:24,y:70),.init(x:31,y:77),.init(x:22,y:90),.init(x:13,y:83)])
        ray([.init(x:46,y:83),.init(x:57,y:81),.init(x:62,y:94),.init(x:44,y:97)])
        ray([.init(x:77,y:61),.init(x:93,y:67),.init(x:86,y:79),.init(x:73,y:71)])

        let disc=NSBezierPath()
        disc.move(to:.init(x:49,y:29))
        disc.curve(to:.init(x:74,y:51),controlPoint1:.init(x:62,y:27),controlPoint2:.init(x:73,y:36))
        disc.curve(to:.init(x:51,y:77),controlPoint1:.init(x:75,y:65),controlPoint2:.init(x:64,y:76))
        disc.curve(to:.init(x:24,y:54),controlPoint1:.init(x:36,y:79),controlPoint2:.init(x:24,y:68))
        disc.curve(to:.init(x:49,y:29),controlPoint1:.init(x:23,y:41),controlPoint2:.init(x:35,y:30))
        disc.close();shape(disc,fill:gold)
        // A rounded wink and a lifted eye frame the lopsided smile.
        let wink=NSBezierPath()
        wink.move(to:.init(x:34,y:49.5))
        wink.curve(to:.init(x:45.5,y:48),controlPoint1:.init(x:37,y:44.5),controlPoint2:.init(x:41.5,y:44))
        wink.lineWidth=5.7;wink.lineCapStyle = .round;forest.setStroke();wink.stroke()
        forest.setFill()
        NSBezierPath(ovalIn:.init(x:56,y:39,width:9,height:12)).fill()

        let grin=NSBezierPath()
        grin.move(to:.init(x:37.5,y:56))
        grin.curve(to:.init(x:64.5,y:53),controlPoint1:.init(x:45,y:60),controlPoint2:.init(x:56,y:59))
        grin.curve(to:.init(x:66,y:54.5),controlPoint1:.init(x:65.5,y:52.3),controlPoint2:.init(x:66.5,y:53.4))
        grin.curve(to:.init(x:49.5,y:68),controlPoint1:.init(x:64,y:64),controlPoint2:.init(x:56.5,y:69.5))
        grin.curve(to:.init(x:36,y:57),controlPoint1:.init(x:43.5,y:67),controlPoint2:.init(x:39,y:63))
        grin.curve(to:.init(x:37.5,y:56),controlPoint1:.init(x:35.5,y:55.8),controlPoint2:.init(x:36.5,y:55.4))
        grin.close();grin.fill()

        let runaway:[NSPoint]=[.init(x:74,y:33),.init(x:78,y:23),.init(x:85,y:21),.init(x:88,y:13),
                               .init(x:96,y:16),.init(x:90,y:27),.init(x:83,y:28)]
        shape(polygon(runaway.map{.init(x:$0.x+kick*0.32,y:$0.y-kick*0.52)}),fill:color(0xFF9945))
    }

    static func artwork(size:NSSize, padding:CGFloat)->NSImage {
        NSImage(size:size,flipped:true) { rect in
            drawSun(in:rect.insetBy(dx:padding,dy:padding),kick:0)
            return true
        }
    }

    static func image(_ mode:Mode, frame:Frame = .resting)->NSImage {
        let key=Key(mode:mode,frame:frame)
        if let saved=cache[key] { return saved }
        let im=NSImage(size:size,flipped:true) { _ in
            drawSun(in:.init(x:0.15,y:0.05,width:17,height:17),kick:frame.sparkKick)
            func line(_ x:CGFloat,_ y:CGFloat,_ ex:CGFloat,_ ey:CGFloat,_ hex:Int,_ width:CGFloat) {
                let path=NSBezierPath();path.move(to:.init(x:x,y:y));path.line(to:.init(x:ex,y:ey))
                path.lineCapStyle = .round;path.lineWidth=width;color(hex).setStroke();path.stroke()
            }
            func fill(_ rect:NSRect,_ radius:CGFloat,_ hex:Int) {
                let p=NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius)
                color(hex).setFill();p.fill()
            }
            // The right-hand badges report state; the amber ray is just branding.
            if mode == .solar {
                let horizon=NSBezierPath();horizon.appendArc(withCenter:.init(x:20.15,y:13.6),radius:1.9,startAngle:180,endAngle:360)
                horizon.close();color(0xFFC66B).setFill();horizon.fill()
                line(17.9,14.05,22.4,14.05,0x142E26,1.3)
                line(18.15,14.05,22.15,14.05,0xFFC66B,0.65)
            } else if mode == .attention {
                let badge=polygon([.init(x:20.2,y:9.5),.init(x:22.75,y:14.9),.init(x:17.65,y:14.9)])
                color(0xFA8961).setFill();badge.fill()
                color(0x142E26).setStroke();badge.lineWidth=0.55;badge.stroke()
                line(20.2,11.4,20.2,12.65,0x142E26,0.75)
                fill(.init(x:19.84,y:13.35,width:0.72,height:0.72),0.3,0x142E26)
            }
            return true
        }
        im.isTemplate=false;im.accessibilityDescription=mode.label;cache[key]=im
        return im
    }
}

/// No heartbeat or idle timer. At most ten delayed frames for one menu opening.
@MainActor final class DeskMarkCue {
    private(set) var frame:DeskMark.Frame = .resting
    private var task:Task<Void,Never>?
    func open(reduced:@escaping @MainActor ()->Bool, draw:@escaping @MainActor ()->Void) {
        task?.cancel();task=nil
        if reduced() {frame = .settled;draw();return}
        let clock=ContinuousClock(), start=clock.now, step=Duration.milliseconds(22)
        frame = .start;draw()
        task=Task { [weak self] in
            for f in DeskMark.Frame.allCases where f.rawValue>0 {
                do {try await clock.sleep(until:start+step*f.rawValue)} catch {return}
                guard !Task.isCancelled,let self else{return}
                if reduced() || clock.now>=start+step*DeskMark.Frame.settled.rawValue {
                    self.frame = .settled;draw();self.task=nil;return
                }
                self.frame=f;draw()
            }
            self?.task=nil
        }
    }
    func reset() { task?.cancel();task=nil;frame = .resting }
}
