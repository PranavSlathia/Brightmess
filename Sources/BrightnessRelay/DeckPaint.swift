import AppKit
import SwiftUI
import BrightnessHardware

enum DeckPaint {
    private static func rgb(_ hex:Int)->NSColor {
        NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
    }
    private static func adaptive(_ light:Int,_ dark:Int)->Color {
        Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? rgb(dark):rgb(light)})
    }
    static let ground=adaptive(0xf0f3e8,0x192c24),ink=adaptive(0x153d2e,0xf0f4df)
    static let muted=adaptive(0x3d574a,0xc0cebb),rule=adaptive(0xa0b09a,0x576e60)
    static let shelf=adaptive(0xe4edcf,0x243d30),button=adaptive(0xf6f8ed,0x2c4436)
    static let accent=adaptive(0x204834,0xd4e6b5),onAccent=adaptive(0xfffcf2,0x14261d)
    static let forest=Color(nsColor:rgb(0x153d2f)),cream=Color(nsColor:rgb(0xf4f9e9))
    static let pear=Color(nsColor:rgb(0xddebba)),leaf=Color(nsColor:rgb(0xc5ed70))
}

struct DeckDisplayGlyph: View {
    let display:ExternalDisplay
    var body:some View {
        Group {
            if let w=display.desktopWidth,let h=display.desktopHeight,w>0,h>0 {
                let scale=min(24/w,22/h)
                RoundedRectangle(cornerRadius:2).strokeBorder(lineWidth:1.5)
                    .frame(width:max(2,w*scale),height:max(2,h*scale))
            } else { Image(systemName:"display").font(.caption) }
        }.frame(width:27,height:25).accessibilityHidden(true)
    }
}
