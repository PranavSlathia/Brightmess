import CoreGraphics

/// Resolves geometry only for the original window, never by app name or size.
public enum WindowGeometry {
    public struct Record {
        public let id:UInt32,owner:Int32,frame:CGRect
        public init(id:UInt32,owner:Int32,frame:CGRect){self.id=id;self.owner=owner;self.frame=frame}
    }
    public static func resolve(accessibility:CGRect?,windowID:UInt32?,owner:Int32,
                               records:[Record]?)->CGRect? {
        func valid(_ frame:CGRect?)->CGRect? {
            guard let frame,!frame.isNull,!frame.isInfinite,!frame.isEmpty,
                  frame.minX.isFinite,frame.minY.isFinite,frame.width.isFinite,frame.height.isFinite else{return nil}
            return frame
        }
        guard let windowID,windowID != 0,let records else{return valid(accessibility)}
        let exact=records.filter{$0.id==windowID}
        // An available snapshot with a missing/reused/ambiguous ID is not a
        // license to use stale AX coordinates or select a same-sized sibling.
        guard exact.count==1,let record=exact.first,record.owner==owner else{return nil}
        guard let frame=valid(record.frame) else{return nil}
        // WindowServer reports presentation transforms during full-screen
        // animations. AX size is the logical window size; do not move/resize
        // from a half-scale animation rectangle. AX origin may still be stale.
        if let ax=valid(accessibility),
           abs(ax.width-frame.width)>2 || abs(ax.height-frame.height)>2 {return nil}
        return frame
    }
}
