import Foundation
import CoreGraphics

public struct ArrangementWindow:Identifiable,Equatable {
    public let id:String,app:String,title:String,frame:CGRect,minimum:CGSize,resizable:Bool
    public init(id:String,app:String,title:String,frame:CGRect,minimum:CGSize = CGSize(width:320,height:200),resizable:Bool = true) {
        self.id=id;self.app=app;self.title=title;self.frame=frame;self.minimum=minimum;self.resizable=resizable
    }
}
public struct ArrangementDisplay:Equatable {
    public let id:UInt32,name:String,usable:CGRect,scale:CGFloat
    public init(id:UInt32,name:String,usable:CGRect,scale:CGFloat=1){self.id=id;self.name=name;self.usable=usable;self.scale=scale}
}
public struct ArrangementPlan:Equatable {
    public struct Item:Equatable {
        public let window:ArrangementWindow,zone:CGRect,target:CGRect
        public init(window:ArrangementWindow,zone:CGRect,target:CGRect){self.window=window;self.zone=zone;self.target=target}
    }
    public let display:ArrangementDisplay,items:[Item],label:String
    public init(display:ArrangementDisplay,items:[Item],label:String){self.display=display;self.items=items;self.label=label}
}
public enum ArrangementMode:String,CaseIterable {case smart,equal}
public enum ArrangementPlanner {
    public static func valid(_ r:CGRect)->Bool {
        !r.isNull && !r.isInfinite && !r.isEmpty && [r.minX,r.minY,r.width,r.height].allSatisfy{$0.isFinite}
    }
    public static func near(_ a:CGRect,_ b:CGRect,tolerance:CGFloat=2)->Bool {
        valid(a) && valid(b) && abs(a.minX-b.minX)<=tolerance && abs(a.minY-b.minY)<=tolerance && abs(a.width-b.width)<=tolerance && abs(a.height-b.height)<=tolerance
    }
    public static func plan(windows:[ArrangementWindow],display:ArrangementDisplay,mode:ArrangementMode)->ArrangementPlan? {
        guard (1...16).contains(windows.count),Set(windows.map(\.id)).count==windows.count,
              valid(display.usable),display.usable.width<100_000,display.usable.height<100_000,
              display.scale.isFinite,(0.25...4).contains(display.scale),
              windows.allSatisfy({valid($0.frame) && $0.minimum.width.isFinite && $0.minimum.height.isFinite && (0..<100_000).contains($0.minimum.width) && (0..<100_000).contains($0.minimum.height)}) else{return nil}
        let ordered=windows.sorted{a,b in a.frame.minY != b.frame.minY ? a.frame.minY<b.frame.minY : a.frame.minX != b.frame.minX ? a.frame.minX<b.frame.minX : a.id<b.id}
        let area=display.usable.insetBy(dx:8,dy:8),gap:CGFloat=8
        guard valid(area) else{return nil}
        func allocate(_ list:[ArrangementWindow],in area:CGRect,direction:ArrangementGrid.Direction,subdivision:Int)->[CGRect]? {
            let scale=display.scale,w=Int(floor(area.width*scale)),h=Int(floor(area.height*scale))
            guard w>0,h>0 else{return nil}
            let constraints=list.map { window -> ArrangementGrid.WindowConstraints in
                let minimum=window.resizable ? window.minimum:window.frame.size
                func limit(_ value:CGFloat,_ maximum:Int)->ArrangementGrid.Constraint {
                    let required=ceil((value+gap)*scale)
                    let lower=required>CGFloat(maximum) ? maximum+1:Int(required)
                    return .resizable(minimum:mode == .equal ? 0:lower,maximum:maximum)
                }
                return .init(width:limit(minimum.width,w),height:limit(minimum.height,h))
            }
            let allocation=ArrangementGrid.layout(bounds:.init(CGRect(x:0,y:0,width:w,height:h)),direction:direction,subdivision:subdivision,constraints:constraints)
            guard allocation.feasible else{return nil}
            // Upstream uses bottom-left backing pixels; our boundary is global
            // top-left AX points. Convert once, then leave native writes outside.
            return allocation.frames.map{CGRect(x:area.minX+$0.minX/scale,y:area.minY+(CGFloat(h)-$0.maxY)/scale,width:$0.width/scale,height:$0.height/scale).insetBy(dx:gap/2,dy:gap/2)}
        }
        var candidates=[([CGRect],String)]()
        if mode == .equal {
            // A partially occupied final row is preferable to calling visibly
            // unequal zones "Equal". All allocated cells have the same size.
            let scale=display.scale,w=Int(floor(area.width*scale)),h=Int(floor(area.height*scale))
            for columns in 1...ordered.count {
                let rows=(ordered.count+columns-1)/columns
                let constraints=Array(repeating:ArrangementGrid.WindowConstraints(width:.resizable(minimum:0,maximum:w),height:.resizable(minimum:0,maximum:h)),count:rows*columns)
                let layout=ArrangementGrid.layout(bounds:.init(CGRect(x:0,y:0,width:w,height:h)),direction:.rows,subdivision:columns,constraints:constraints)
                if layout.feasible {
                    let frames=layout.frames.prefix(ordered.count).map{CGRect(x:area.minX+$0.minX/scale,y:area.minY+(CGFloat(h)-$0.maxY)/scale,width:$0.width/scale,height:$0.height/scale).insetBy(dx:gap/2,dy:gap/2)}
                    candidates.append((frames,"Equal grid"))
                }
            }
        } else {
            for direction in [ArrangementGrid.Direction.rows,.columns] {
                for subdivision in 1...ordered.count {
                    if let frames=allocate(ordered,in:area,direction:direction,subdivision:subdivision) {
                        candidates.append((frames,direction == .rows ? "Balanced rows":"Balanced columns"))
                    }
                }
            }
        }
        if mode == .smart,ordered.count>2 {
            for vertical in [true,false] {
                for fraction in [CGFloat(0.5),0.6] {
                    let first:CGRect,rest:CGRect
                    if vertical {
                        first=CGRect(x:area.minX,y:area.minY,width:area.width,height:area.height*fraction)
                        rest=CGRect(x:area.minX,y:first.maxY,width:area.width,height:area.height-first.height)
                    } else {
                        first=CGRect(x:area.minX,y:area.minY,width:area.width*fraction,height:area.height)
                        rest=CGRect(x:first.maxX,y:area.minY,width:area.width-first.width,height:area.height)
                    }
                    for direction in [ArrangementGrid.Direction.rows,.columns] {
                        for subdivision in 1..<ordered.count {
                            if let frames=allocate(Array(ordered.dropFirst()),in:rest,direction:direction,subdivision:subdivision) {
                                candidates.append(([first.insetBy(dx:gap/2,dy:gap/2)]+frames,"Main pane + companions"))
                            }
                        }
                    }
                }
            }
        }
        func items(_ frames:[CGRect])->[ArrangementPlan.Item]? {
            guard frames.count==ordered.count else{return nil}
            var result=[ArrangementPlan.Item]()
            for (window,zone) in zip(ordered,frames) {
                let minimum=window.resizable ? window.minimum:window.frame.size
                guard valid(zone),display.usable.contains(zone),zone.width+0.5>=minimum.width,zone.height+0.5>=minimum.height else{return nil}
                let target=window.resizable ? zone:CGRect(x:zone.midX-window.frame.width/2,y:zone.midY-window.frame.height/2,width:window.frame.width,height:window.frame.height)
                result.append(.init(window:window,zone:zone,target:target))
            }
            for i in frames.indices {for j in frames.indices where j>i {if !frames[i].intersection(frames[j]).isEmpty{return nil}}}
            return result
        }
        func score(_ items:[ArrangementPlan.Item])->Double {
            let mean=items.reduce(CGFloat(0)){$0+$1.zone.width*$1.zone.height}/CGFloat(items.count)
            return items.reduce(0) { sum,item in
                let preferred=mode == .smart ? min(2.2,max(0.55,item.window.frame.width/item.window.frame.height)):CGFloat(1.35)
                let aspect=abs(log(Double((item.zone.width/item.zone.height)/preferred)))
                let balance=abs(Double(item.zone.width*item.zone.height/mean-1))
                let movement=hypot(Double((item.zone.midX-item.window.frame.midX)/area.width),Double((item.zone.midY-item.window.frame.midY)/area.height))
                return sum+aspect+balance*(mode == .equal ? 4:0.18)+movement*0.08
            }
        }
        return candidates.compactMap{frames,label -> (ArrangementPlan,Double)? in
            guard let values=items(frames) else{return nil}
            return (.init(display:display,items:values,label:label),score(values))
        }.min{$0.1<$1.1}?.0
    }
}
