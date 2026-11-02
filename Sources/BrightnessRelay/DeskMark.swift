import AppKit

/// A template, not a status light: miniature display bounds in desktop order.
@MainActor enum DeskMark {
    enum Mode: CaseIterable,Hashable { case linked,solar,attention }
    private struct Key:Hashable { let mode:Mode;let aspects:[Int] }
    private static var cache=[Key:NSImage]()
    static func image(_ mode:Mode)->NSImage {
        let ratios=NSScreen.screens.sorted{$0.frame.minX<$1.frame.minX}.prefix(2).map{
            Int((100*$0.frame.width/max(1,$0.frame.height)).rounded())
        }
        let key=Key(mode:mode,aspects:ratios)
        if let saved=cache[key]{return saved}
        if cache.count>24{cache.removeAll()}
        let image=NSImage(size:NSSize(width:23,height:17),flipped:true){_ in
            NSColor.black.setStroke();NSColor.black.setFill()
            func line(_ x:CGFloat,_ y:CGFloat,_ ex:CGFloat,_ ey:CGFloat,_ width:CGFloat=1.35){
                let p=NSBezierPath();p.lineWidth=width;p.lineCapStyle = .round
                p.move(to:.init(x:x,y:y));p.line(to:.init(x:ex,y:ey));p.stroke()
            }
            let aspects=ratios.isEmpty ? [100]:ratios
            let widths=aspects.map{min(13.0,max(4,10.5*CGFloat($0)/100))}
            let fit=min(1,19.5/(widths.reduce(0,+))),gap:CGFloat=2.5
            var x=(23-(widths.reduce(0,+)*fit+CGFloat(aspects.count-1)*gap))/2
            var skyX:CGFloat=11.5, widest:CGFloat=0
            for (i,a) in aspects.enumerated(){
                let w=widths[i]*fit,h=min(10.5,w*100/CGFloat(max(1,a))),y=13-h
                let p=NSBezierPath(roundedRect:.init(x:x,y:y,width:w,height:h),xRadius:1.0,yRadius:1.0)
                p.lineWidth=1.45;p.stroke()
                line(x+w*0.3,15.2,x+w*0.7,15.2)
                if w>widest {widest=w;skyX=x+w/2}
                x+=w+gap
            }
            // A tall screen leaves little sky above it; put the cue beside it.
            if aspects.allSatisfy({$0<105}){skyX=2.9}
            switch mode{
            case .linked:line(skyX-2,1.4,skyX+2,1.4)
            case .solar:
                let p=NSBezierPath();p.appendArc(withCenter:.init(x:skyX,y:3.25),radius:2.05,startAngle:180,endAngle:360)
                p.lineWidth=1.3;p.stroke()
            case .attention:line(skyX,0.7,skyX,1.8);NSBezierPath(ovalIn:.init(x:skyX-0.65,y:3,width:1.3,height:1.3)).fill()
            }
            return true
        }
        image.isTemplate=true;image.accessibilityDescription="BRIGHTMESS";cache[key]=image;return image
    }
}
