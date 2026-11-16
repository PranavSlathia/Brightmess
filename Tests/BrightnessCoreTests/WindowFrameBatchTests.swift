import Foundation
import CoreGraphics
import Testing
@testable import BrightnessCore

@Test func retrievalFirstAttemptSurvivesAnimatedResizeDroppingPosition() async throws {
    let portrait=CGRect(x:0,y:0,width:1440,height:2560),tv=CGRect(x:-1920,y:0,width:1920,height:1080)
    var frame=CGRect(x:100,y:100,width:900,height:1800),clock=0.0,enhanced=true,animation=false,batches=0
    try await WindowRetrieval.run(original:1,destination:2,read:{
        .init(screen:frame.minX<0 ? 2:1,rect:frame,usable:frame.minX<0 ? tv:portrait,
            fullFrame:frame.minX<0 ? tv:portrait,fullScreen:false,canExitFullScreen:false,movable:true)
    },target:{tv},exitFullScreen:{},write:{target in
        batches+=1
        try WindowFrameBatch.write(target,resize:true,assistiveTechnologyActive:false,validate:{},
            readEnhanced:{enhanced},setEnhanced:{enhanced=$0;return true},setSize:{size in
                animation=enhanced && frame.size != size;frame.size=size
            },setPosition:{point in if !animation {frame.origin=point}})
    },pause:{clock+=0.1},now:{clock})
    #expect(frame.minX<0 && batches==1 && enhanced)
}

@Test func frameBatchRestoresStateOnRefusalAndCancellation() {
    for cancelled in [false,true] {
        var enhanced=true,states=[Bool](),positions=0
        #expect(throws:(any Error).self) {
            try WindowFrameBatch.write(CGRect(x:0,y:0,width:500,height:500),resize:true,assistiveTechnologyActive:false,
                validate:{},readEnhanced:{enhanced},setEnhanced:{enhanced=$0;states.append($0);return true},
                setSize:{_ in if cancelled {throw CancellationError()} else {throw TVError("Refused")}},
                setPosition:{_ in positions+=1})
        }
        #expect(enhanced && states==[false,true] && positions==0)
    }
}

@Test func frameBatchPreservesAssistiveToolsAndRejectsChangedIdentity() throws {
    var settings=[Bool](),valid=true,positions=0
    #expect(throws:TVError.self) {
        try WindowFrameBatch.write(CGRect(x:0,y:0,width:500,height:500),resize:true,assistiveTechnologyActive:true,
            validate:{if !valid {throw TVError("Original closed")}},readEnhanced:{true},setEnhanced:{settings.append($0);return true},
            setSize:{_ in valid=false},setPosition:{_ in positions+=1})
    }
    #expect(settings.isEmpty && positions==0)
}

@Test func frameBatchDoesNotEnableUnknownOrDisabledEnhancedUI() throws {
    for initial:Bool? in [nil,false] {
        var changes=0,positions=0
        try WindowFrameBatch.write(CGRect(x:0,y:0,width:500,height:500),resize:false,assistiveTechnologyActive:false,
            validate:{},readEnhanced:{initial},setEnhanced:{_ in changes+=1;return true},setSize:{_ in Issue.record("Unexpected resize")},setPosition:{_ in positions+=1})
        #expect(changes==0 && positions==1)
    }
}

@Test func frameBatchRepairsPartialGuardFailureAndSurfacesRestoreFailure() throws {
    var enabled=true,settings=[Bool]()
    try ArrangementAdjustment.perform(assistiveTechnologyActive:false,readEnabled:{enabled},setEnabled:{
        enabled=$0;settings.append($0);return $0
    },adjust:{#expect(enabled)})
    #expect(enabled && settings==[false,true])
    var positionWrites=0
    #expect(throws:TVError.self) {
        try WindowFrameBatch.write(CGRect(x:0,y:0,width:500,height:500),resize:false,assistiveTechnologyActive:false,
            validate:{},readEnhanced:{true},setEnhanced:{$0 == false},setSize:{_ in},setPosition:{_ in positionWrites+=1})
    }
    #expect(positionWrites==1)
}
