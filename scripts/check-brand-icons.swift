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
            if c.greenComponent>c.redComponent+0.04 && c.greenComponent>c.blueComponent+0.015 {result.0+=1}
            if c.redComponent>0.58 && c.redComponent>c.greenComponent+0.12 && c.redComponent>c.blueComponent+0.35 {result.1+=1}
        }}
        return result
    }
    // Count the amber ray, excluding the right-hand status badge, and measure
    // its vertical centroid without assuming bitmap row orientation.
    static func spark(_ rep:NSBitmapImageRep,scale:Int)->Double {
        var pixelY=0, pixelCount=0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<min(17*scale,rep.pixelsWide) {
                guard let c=rep.colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else{continue}
                if c.alphaComponent>0.65 && c.redComponent>0.80 && (0.47...0.69).contains(c.greenComponent) && c.blueComponent<0.48 {
                    pixelY+=y;pixelCount+=1
                }
            }
        }
        precondition(pixelCount>0,"Runaway ray is missing at native size")
        return Double(pixelY)/Double(pixelCount)
    }
    static func checkCue() async throws {
        let cue=DeskMarkCue();var frames=[DeskMark.Frame]()
        cue.open(reduced:{true}){frames.append(cue.frame)}
        precondition(frames == [.settled],"Reduce Motion must present only the final frame")
        frames=[];cue.open(reduced:{false}){frames.append(cue.frame)}
        let limit=ContinuousClock.now + .seconds(2)
        while frames.last != .settled && ContinuousClock.now<limit {try await Task.sleep(for:.milliseconds(12))}
        precondition(frames.first == .start && frames.last == .settled && frames.count<=11,"Opening did not settle")
        let n=frames.count;try await Task.sleep(for:.milliseconds(55));precondition(n==frames.count)
        frames=[];cue.open(reduced:{false}){frames.append(cue.frame)};cue.reset()
        try await Task.sleep(for:.milliseconds(80))
        precondition(cue.frame == .resting && frames == [.start],"A closed menu continued animating")
    }
    static func main() async throws {
        if CommandLine.arguments[1] == "--artwork" {
            let size=NSSize(width:1024,height:1024)
            let sun=DeskMark.artwork(size:size,padding:128)
            let art=bitmap(size){sun.draw(in:$0)}
            try art.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
            return
        }
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        let url=URL(fileURLWithPath:CommandLine.arguments[2])
        guard let b=Bundle(url:url), b.object(forInfoDictionaryKey:"CFBundleIconName") as? String=="BRIGHTMESS",
              b.url(forResource:"BRIGHTMESS",withExtension:"icns") != nil,
              b.url(forResource:"Assets",withExtension:"car") != nil else {fatalError("Missing bundle icon declarations or resources")}
        let fileIcon=NSWorkspace.shared.icon(forFile:url.path)
        let iconPixels=pixels(bitmap(.init(width:128,height:128)){fileIcon.draw(in:$0)})
        precondition(iconPixels.green>400 && iconPixels.warm>400,"Icon Services returned generic or unrecognizable artwork: \(iconPixels)")
        for scale in [1,2] {
            var states=Set<Data>()
            for mode in DeskMark.Mode.allCases {
                let image=DeskMark.image(mode)
                precondition(!image.isTemplate && image.size==DeskMark.size && image === DeskMark.image(mode))
                let rep=bitmap(image.size,scale:scale){image.draw(in:$0)}
                let count=pixels(rep)
                precondition(count.warm>35*scale*scale && count.clear>16*scale*scale)
                _=spark(rep,scale:scale)
                states.insert(rep.representation(using:.png,properties:[:])!)
            }
            precondition(states.count==3,"Status modes indistinguishable")
        }
        let rest=bitmap(DeskMark.size,scale:2){DeskMark.image(.linked).draw(in:$0)}
        let start=bitmap(DeskMark.size,scale:2){DeskMark.image(.linked,frame:.start).draw(in:$0)}
        let settle=bitmap(DeskMark.size,scale:2){DeskMark.image(.linked,frame:.settled).draw(in:$0)}
        precondition(rest.representation(using:.png,properties:[:])==settle.representation(using:.png,properties:[:]) &&
            abs(spark(start,scale:2)-spark(settle,scale:2))>1,"Ray must flick and return to its resting position")
        try await checkCue()
        let foreground=NSColor(srgbRed:0.08,green:0.20,blue:0.15,alpha:1)
        func label(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .medium) {
            (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:foreground])
        }
        func sheet(scale:Int)->NSBitmapImageRep { bitmap(NSSize(width:518,height:194),scale:scale){rect in
            NSColor(srgbRed:0.94,green:0.95,blue:0.90,alpha:1).setFill();rect.fill()
            label("BRIGHTMESS",16,160,16,.bold);label("The brightest mess.",16,144,11)
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
        } }
        try sheet(scale:2).representation(using:.png,properties:[:])!.write(to:output,options:.atomic)
        if CommandLine.arguments.count>3, !CommandLine.arguments[3].isEmpty {
            try sheet(scale:1).representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[3]),options:.atomic)
        }
        print("Icon Services, all three 1×/2× marks, runaway ray, one-shot motion and Reduce Motion passed. Proof: "+output.path)
    }
}
