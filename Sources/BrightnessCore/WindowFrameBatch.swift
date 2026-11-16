import CoreGraphics

/// One resize/position/resize operation, bound to an exact window by the adapter.
/// Geometry is read by the transaction after the batch, never between its writes.
public enum WindowFrameBatch {
    public static func write(_ frame:CGRect,resize:Bool,assistiveTechnologyActive:Bool,
        validate:()throws->Void,readEnhanced:()->Bool?,setEnhanced:(Bool)->Bool,
        setSize:(CGSize)throws->Void,setPosition:(CGPoint)throws->Void) throws {
        guard frame.minX.isFinite,frame.minY.isFinite,frame.width.isFinite,frame.height.isFinite,
              frame.width>0,frame.height>0 else{throw TVError("Invalid window target. No move sent.")}
        try validate()
        try ArrangementAdjustment.perform(assistiveTechnologyActive:assistiveTechnologyActive,
            readEnabled:readEnhanced,setEnabled:setEnhanced) {
            try validate()
            if resize {try setSize(frame.size)}
            try validate()
            try setPosition(frame.origin)
            try validate()
            if resize {try setSize(frame.size)}
        }
    }
}
