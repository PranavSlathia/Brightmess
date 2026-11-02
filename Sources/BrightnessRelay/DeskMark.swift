import AppKit

/// Out of Register: a shared brightness stripe and a single deliberately misplaced pixel.
/// The brand mark stays fixed; the display controls, not this icon, show live desk geometry.
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
        case resting = -1, start, one, two, three, four, five, six, seven, eight, nine, aligned
        var progress: CGFloat { CGFloat(max(0,rawValue)) / CGFloat(Frame.aligned.rawValue) }
        var stripeOffset: CGFloat {
            self == .resting ? 0 : 1.4 * pow(1-min(1,progress*1.375),2)
        }
        var pixelAlignment: CGFloat {
            self == .resting ? 0 : min(1,max(0,(progress-0.52)/0.48))
        }
    }
    private struct Key: Hashable { let mode: Mode, frame: Frame }
    static let size = NSSize(width:23,height:17)
    private static var cache=[Key:NSImage]()

    static func image(_ mode:Mode, frame:Frame = .resting)->NSImage {
        let key=Key(mode:mode,frame:frame)
        if let saved=cache[key] { return saved }
        let im=NSImage(size:size,flipped:true) { _ in
            func color(_ hex:Int)->NSColor {
                NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
            }
            func line(_ x:CGFloat,_ y:CGFloat,_ ex:CGFloat,_ ey:CGFloat,_ hex:Int,_ width:CGFloat) {
                let path=NSBezierPath();path.move(to:.init(x:x,y:y));path.line(to:.init(x:ex,y:ey))
                path.lineCapStyle = .round;path.lineWidth=width;color(hex).setStroke();path.stroke()
            }
            func fill(_ rect:NSRect,_ radius:CGFloat,_ hex:Int) {
                let p=NSBezierPath(roundedRect:rect,xRadius:radius,yRadius:radius)
                color(hex).setFill();p.fill()
            }
            let glass=NSGradient(colors:[color(0x4A9989),color(0x155544),color(0x0B302B)])!
            func panel(_ r:NSRect,_ radius:CGFloat) {
                let p=NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius)
                glass.draw(in:p,angle:51)
                color(0x83C4AC).setStroke();p.lineWidth=0.8;p.stroke()
            }
            panel(.init(x:0.65,y:6,width:11.85,height:7),1.1)
            panel(.init(x:13.75,y:2,width:6.2,height:11),1)
            line(3.1,13.2,1.9,14.8,0x21604A,1.1); line(9.6,13.2,10.8,14.8,0x21604A,1.1)
            line(16.85,13.3,16.85,15.1,0x21604A,1.1); line(15,15.3,18.7,15.3,0x21604A,1.1)
            let y=9+frame.stripeOffset
            fill(.init(x:1.25,y:y,width:10.65,height:1.8),0.16,0xCAFF40)
            fill(.init(x:14.35,y:y,width:4.98,height:1.8),0.16,0xCAFF40)
            let t=frame.pixelAlignment
            let pixel=NSBezierPath(roundedRect:.init(x:20.65-0.35*t,y:6.85+2.15*t,width:1.85,height:1.85),xRadius:0.2,yRadius:0.2)
            color(0xFFAE3C).setFill();pixel.fill()
            color(0x8E4E21).setStroke();pixel.lineWidth=0.45;pixel.stroke()
            // Small mode cues use the empty space above the wide TV, not the stripe or stray pixel.
            if mode == .solar {
                let sun=NSBezierPath();sun.appendArc(withCenter:.init(x:5.6,y:4.4),radius:2.6,startAngle:180,endAngle:360)
                sun.close();color(0xFFB54E).setFill();sun.fill()
                line(2.5,4.5,8.7,4.5,0x966324,0.85)
            } else if mode == .attention {
                let badge=NSBezierPath();badge.move(to:.init(x:5.6,y:0.2));badge.line(to:.init(x:8.7,y:5.1));badge.line(to:.init(x:2.5,y:5.1));badge.close()
                color(0xFA8961).setFill();badge.fill()
                line(5.6,1.8,5.6,3,0x452A20,0.75);fill(.init(x:5.22,y:3.65,width:0.76,height:0.76),0.3,0x452A20)
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
        if reduced() {frame = .aligned;draw();return}
        let clock=ContinuousClock(), start=clock.now, step=Duration.milliseconds(22)
        frame = .start;draw()
        task=Task { [weak self] in
            for f in DeskMark.Frame.allCases where f.rawValue>0 {
                do {try await clock.sleep(until:start+step*f.rawValue)} catch {return}
                guard !Task.isCancelled,let self else{return}
                if reduced() || clock.now>=start+step*DeskMark.Frame.aligned.rawValue {
                    self.frame = .aligned;draw();self.task=nil;return
                }
                self.frame=f;draw()
            }
            self?.task=nil
        }
    }
    func reset() { task?.cancel();task=nil;frame = .resting }
}
