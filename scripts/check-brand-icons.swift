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
            if c.redComponent>0.58 && c.redComponent>c.blueComponent+0.35 && c.greenComponent>0.25 {result.1+=1}
        }}
        return result
    }
    static func main() throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1])
        let url=URL(fileURLWithPath:CommandLine.arguments[2])
        guard let b=Bundle(url:url), b.object(forInfoDictionaryKey:"CFBundleIconName") as? String=="BRIGHTMESS",
              b.url(forResource:"BRIGHTMESS",withExtension:"icns") != nil,
              b.url(forResource:"Assets",withExtension:"car") != nil,
              b.url(forResource:"FireflyMenu",withExtension:"png") != nil else {fatalError("Missing bundle icon declarations or resources")}
        let fileIcon=NSWorkspace.shared.icon(forFile:url.path)
        let iconPixels=pixels(bitmap(.init(width:128,height:128)){fileIcon.draw(in:$0)})
        precondition(iconPixels.green>400 && iconPixels.warm>60,"Icon Services returned generic or unrecognizable artwork")
        for scale in [1,2] {
            var states=Set<Data>()
            for mode in DeskMark.Mode.allCases {
                let image=DeskMark.image(mode)
                precondition(!image.isTemplate && image.size==DeskMark.size && image === DeskMark.image(mode))
                let rep=bitmap(image.size,scale:scale){image.draw(in:$0)}
                let count=pixels(rep)
                precondition(count.green>10 && count.warm>4 && count.clear>16)
                states.insert(rep.representation(using:.png,properties:[:])!)
            }
            precondition(states.count==3,"Status modes indistinguishable")
        }
        // Independent reference for the resting mark: ensures the packaged
        // optical artwork was used, not a missing-resource fallback.
        let file=NSImage(contentsOf:Bundle.main.url(forResource:"FireflyMenu",withExtension:"png")!)!
        let f=min(22/file.size.width,17/file.size.height),art=NSSize(width:file.size.width*f,height:file.size.height*f)
        let expected=bitmap(DeskMark.size,scale:2){r in file.draw(in:NSRect(x:r.midX-art.width/2,y:r.midY-art.height/2,width:art.width,height:art.height))}
        let actual=bitmap(DeskMark.size,scale:2){DeskMark.image(.linked).draw(in:$0)}
        let a=pixels(actual),e=pixels(expected)
        precondition(abs(a.green-e.green)<32 && abs(a.warm-e.warm)<30,"Resting icon is not the optical master")
        let foreground=NSColor(srgbRed:0.08,green:0.20,blue:0.15,alpha:1)
        func label(_ s:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ weight:NSFont.Weight = .medium) {
            (s as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:foreground])
        }
        let sheet=bitmap(NSSize(width:518,height:194),scale:2){rect in
            NSColor(srgbRed:0.94,green:0.95,blue:0.90,alpha:1).setFill();rect.fill()
            label("BRIGHTMESS",16,160,16,.bold);label("Glass Firefly",16,144,11)
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
        print("Icon Services artwork and all three full-colour states passed at 1× and 2×. Proof: "+output.path)
    }
}
