import AppKit
import SwiftUI
import BrightnessHardware

enum DeckPaint {
    private static func rgb(_ hex:Int)->NSColor {
        NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1)
    }
    static func adaptive(_ light:Int,_ dark:Int)->Color {
        Color(nsColor:NSColor(name:nil){$0.bestMatch(from:[.aqua,.darkAqua]) == .darkAqua ? rgb(dark):rgb(light)})
    }
    static func fixed(_ hex: Int) -> Color { Color(nsColor: rgb(hex)) }

    static let ground = adaptive(0xffe0a3, 0x923912)
    static let ink = adaptive(0x2b160a, 0xfff3d9)
    static let keyLabel = adaptive(0x2b160a, 0xffffff)
    static let muted = adaptive(0x4e2817, 0xffebd2)
    static let rule = adaptive(0x783110, 0xffe4b9).opacity(0.32)
    static let shelf = fixed(0xffb43e).opacity(0.08)
    static let button = adaptive(0xffe3a8, 0xd48e4a).opacity(0.13)
    static let accent = adaptive(0x7c280b, 0xffe1a8)
    static let amber = fixed(0xffb65c)
    static let glassTint = adaptive(0xffb634, 0xa1430b)
    static let dawn = adaptive(0xffde66, 0x8a3304)
    static let noon = adaptive(0xffac57, 0x86260f)
    static let dusk = adaptive(0xff7e84, 0x74152f)
    static var solarGradient: LinearGradient {
        LinearGradient(colors:[dawn,noon,dusk], startPoint:.topLeading, endPoint:.bottomTrailing)
    }

    static func title(_ size: CGFloat) -> Font { .system(size:size, weight:.semibold, design:.rounded) }
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
