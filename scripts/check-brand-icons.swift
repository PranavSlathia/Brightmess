import AppKit

@main @MainActor enum IconProof {
    static func bitmap(_ size: NSSize, scale:Int=1, draw:(NSRect)->Void)->NSBitmapImageRep {
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width)*scale,pixelsHigh:Int(size.height)*scale,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let ctx=NSGraphicsContext(bitmapImageRep:rep)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=ctx
        ctx.cgContext.clear(CGRect(x:0,y:0,width:rep.pixelsWide,height:rep.pixelsHigh))
        ctx.cgContext.scaleBy(x:CGFloat(scale),y:CGFloat(scale));ctx.imageInterpolation = .high
        draw(NSRect(origin:.zero,size:size));NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    static func pixels(_ rep:NSBitmapImageRep)->(green:Int,warm:Int,clear:Int) {
        var result=(0,0,0)
        for y in 0..<rep.pixelsHigh {for x in 0..<rep.pixelsWide {
            guard let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else{continue}
            if c.alphaComponent<0.1 {result.2+=1;continue}
            if c.greenComponent>c.redComponent+0.1 && c.greenComponent>c.blueComponent+0.10 {result.0+=1}
            if c.redComponent>0.58 && c.redComponent>c.greenComponent+0.12 && c.redComponent>c.blueComponent+0.35 {result.1+=1}
        }}
        return result
    }
    // Find a shared lime row with exactly two runs and the centroid of the stray
    // amber pixel beyond the right bezel. Do not assume bitmap row orientation.
    static func geometry(_ rep:NSBitmapImageRep,scale:Int)->(Int,Double) {
        var bestRow = -1, bestCount = 0, pixelY=0, pixelCount=0
        for y in 0..<rep.pixelsHigh {
            var runs=0,n=0,lit=false
            for x in 0..<rep.pixelsWide {
                guard let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else{continue}
                let signal=c.alphaComponent>0.5 && c.greenComponent>0.87 && c.redComponent>0.55 && c.blueComponent<0.48
                if signal {n+=1;if !lit{runs+=1}};lit=signal
                if x>=20*scale && c.alphaComponent>0.5 && c.redComponent>0.67 && c.greenComponent<c.redComponent-0.12 && c.blueComponent<0.5 {pixelY+=y;pixelCount+=1}
            }
            if runs==2 && n>bestCount { bestRow=y;bestCount=n }
        }
        precondition(bestCount>=9*scale && pixelCount>0,"Missing shared stripe or stray pixel")
        return (bestRow,Double(pixelY)/Double(pixelCount))
    }
    static func checkCue() async throws {
        let cue=DeskMarkCue();var frames=[DeskMark.Frame]()
        cue.open(reduced:{true}){frames.append(cue.frame)}
        precondition(frames == [.aligned],"Reduce Motion must present only the final frame")
        frames=[];cue.open(reduced:{false}){frames.append(cue.frame)}
        let limit=ContinuousClock.now + .seconds(2)
        while frames.last != .aligned && ContinuousClock.now<limit {try await Task.sleep(for:.milliseconds(12))}
        precondition(frames.first == .start && frames.last == .aligned && frames.count<=11,"Opening did not settle")
        let n=frames.count;try await Task.sleep(for:.milliseconds(55));precondition(n==frames.count)
        frames=[];cue.open(reduced:{false}){frames.append(cue.frame)};cue.reset()
        try await Task.sleep(for:.milliseconds(80))
        precondition(cue.frame == .resting && frames == [.start],"A closed menu continued animating")
    }
    static func main() async throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        let url=URL(fileURLWithPath:CommandLine.arguments[2])
        guard let b=Bundle(url:url), b.object(forInfoDictionaryKey:"CFBundleIconName") as? String=="BRIGHTMESS",
              b.url(forResource:"BRIGHTMESS",withExtension:"icns") != nil,
              b.url(forResource:"Assets",withExtension:"car") != nil else {fatalError("Missing bundle icon declarations or resources")}
        let fileIcon=NSWorkspace.shared.icon(forFile:url.path)
        let iconPixels=pixels(bitmap(.init(width:128,height:128)){fileIcon.draw(in:$0)})
        precondition(iconPixels.green>400 && iconPixels.warm>=1,"Icon Services returned generic or unrecognizable artwork")
        for scale in [1,2] {
            var states=Set<Data>()
            for mode in DeskMark.Mode.allCases {
                let image=DeskMark.image(mode)
                precondition(!image.isTemplate && image.size==DeskMark.size && image === DeskMark.image(mode))
                let rep=bitmap(image.size,scale:scale){image.draw(in:$0)}
                let count=pixels(rep)
                precondition(count.green>10 && count.warm>0 && count.clear>16)
                _=geometry(rep,scale:scale)
                states.insert(rep.representation(using:.png,properties:[:])!)
            }
            precondition(states.count==3,"Status modes indistinguishable")
        }
        let rest=geometry(bitmap(DeskMark.size,scale:2){DeskMark.image(.linked).draw(in:$0)},scale:2)
        let start=geometry(bitmap(DeskMark.size,scale:2){DeskMark.image(.linked,frame:.start).draw(in:$0)},scale:2)
        let settle=geometry(bitmap(DeskMark.size,scale:2){DeskMark.image(.linked,frame:.aligned).draw(in:$0)},scale:2)
        precondition(rest.0 == settle.0 && abs(start.0-settle.0)>=2 && abs(rest.1-settle.1)>2,"Incorrect opening positions")
        try await checkCue()
        let foreground=NSColor(srgbRed:0.08,green:0.20,blue:0.15,alpha:1)
        func label(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .medium) {
            (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:foreground])
        }
        let sheet=bitmap(NSSize(width:518,height:194),scale:2){rect in
            NSColor(srgbRed:0.94,green:0.95,blue:0.90,alpha:1).setFill();rect.fill()
            label("BRIGHTMESS",16,160,16,.bold);label("Out of Register",16,144,11)
            fileIcon.draw(in:NSRect(x:16,y:5,width:140,height:140))
            label("Menu bar · 23 × 17 pt",174,147,13,.semibold)
            for (i,mode) in DeskMark.Mode.allCases.enumerated(){
                let x:CGFloat=176+CGFloat(i)*107
                label(["Normal","Solar","Attention"][i],x+6,116,11)
                for (j,color) in [NSColor(white:0.95,alpha:1),NSColor(white:0.07,alpha:1)].enumerated(){
                    let y:CGFloat=77-CGFloat(j)*32
                    color.setFill();NSBezierPath(roundedRect:NSRect(x:x,y:y,width:87,height:25),xRadius:4,yRadius:4).fill()
                    DeskMark.image(mode).draw(in:NSRect(x:x+32,y:y+4,width:23,height:17))
                }
            }
        }
        try sheet.representation(using:.png,properties:[:])!.write(to:output,options:.atomic)
        print("Icon Services, all three 1×/2× marks, stripe alignment, one-shot motion and Reduce Motion passed. Proof: "+output.path)
    }
}
