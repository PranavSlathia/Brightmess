import Testing
@testable import BrightnessCore

@Test func arrangeEnterIgnoresFocusAndRequiresFreshReleasedChord() {
    for key in ["return","enter"] {
        var router=ArrangeKeyRouter();router.opened(modifiers:[.control,.option])
        #expect(router.route(key:key,modifiers:[.control,.option],repeating:false,isKeyWindow:true,phase:.loading,canApply:false,canUndo:false,hasWindows:false) == .pass)
        // Releasing modifiers while still holding Return must not apply on repeat.
        #expect(router.route(key:key,modifiers:[],repeating:true,isKeyWindow:true,phase:.preview,canApply:true,canUndo:false,hasWindows:true) == .consume)
        for _ in ["Close","Smart","Equal","Windows","All","None","Checkbox","Apply"] {
            #expect(router.route(key:key,modifiers:[],repeating:false,isKeyWindow:true,phase:.preview,canApply:true,canUndo:false,hasWindows:true) == .apply)
        }
    }
}
@Test func arrangeKeysNeverQueueApplyOrLeakIntoOtherApps() {
    var router=ArrangeKeyRouter();router.opened(modifiers:[])
    for phase in [ArrangeKeyRouter.Phase.loading,.applying] {
        #expect(router.route(key:"return",modifiers:[],repeating:false,isKeyWindow:true,phase:phase,canApply:false,canUndo:false,hasWindows:true) == .consume)
    }
    #expect(router.route(key:"return",modifiers:[],repeating:false,isKeyWindow:true,phase:.preview,canApply:false,canUndo:false,hasWindows:true) == .consume)
    #expect(router.route(key:"return",modifiers:[],repeating:false,isKeyWindow:false,phase:.preview,canApply:true,canUndo:true,hasWindows:true) == .pass)
    #expect(router.route(key:"return",modifiers:[],repeating:false,isKeyWindow:true,phase:.closed,canApply:true,canUndo:true,hasWindows:true) == .pass)
}
@Test func arrangeSmallKeySetPreservesNativeTraversalAndEditing() {
    var router=ArrangeKeyRouter();router.opened(modifiers:[])
    for (key,expected) in [("s",ArrangeKeyRouter.Action.smart),("e",.equal),("w",.windows),("escape",.close)] {
        #expect(router.route(key:key,modifiers:[],repeating:false,isKeyWindow:true,phase:.preview,canApply:true,canUndo:true,hasWindows:true) == expected)
        #expect(router.route(key:key,modifiers:[],repeating:true,isKeyWindow:true,phase:.preview,canApply:true,canUndo:true,hasWindows:true) == .consume)
    }
    for key in ["tab","space","left","right","up","down","a","r"] {
        #expect(router.route(key:key,modifiers:[],repeating:false,isKeyWindow:true,phase:.preview,canApply:true,canUndo:true,hasWindows:true) == .pass)
    }
    #expect(router.route(key:"z",modifiers:.command,repeating:false,isKeyWindow:true,phase:.result,canApply:false,canUndo:true,hasWindows:true) == .undo)
    #expect(router.route(key:"z",modifiers:.command,repeating:false,isKeyWindow:true,phase:.loading,canApply:false,canUndo:false,hasWindows:true) == .consume)
    #expect(router.route(key:"s",modifiers:[],repeating:false,isKeyWindow:true,phase:.preview,canApply:true,canUndo:true,hasWindows:true,editingText:true) == .pass)
    #expect(router.route(key:"return",modifiers:[],repeating:false,isKeyWindow:true,phase:.result,canApply:false,canUndo:true,hasWindows:true) == .close)
}
