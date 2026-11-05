import Foundation

/// Frame changes must not overlap AppKit enhanced-UI animation. Preserve the
/// application's existing state and never suppress built-in assistive tools.
public enum ArrangementAdjustment {
    public static func perform(assistiveTechnologyActive:Bool,
        readEnabled:()->Bool?,setEnabled:(Bool)->Bool,adjust:()throws->Void)throws {
        guard !assistiveTechnologyActive,readEnabled()==true,setEnabled(false) else{try adjust();return}
        let result=Result(catching:adjust)
        guard setEnabled(true) else{throw TVError("The app's enhanced accessibility state could not be restored. Check that app before continuing.")}
        try result.get()
    }
}
