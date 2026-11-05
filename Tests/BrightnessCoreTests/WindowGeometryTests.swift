import CoreGraphics
import Testing
@testable import BrightnessCore

@Test func animatedWindowServerRectIsNotLogicalWindowGeometry() {
    let logical=CGRect(x:-1230,y:1092,width:540,height:340)
    let animated=CGRect(x:-1096,y:1176,width:272,height:172)
    #expect(WindowGeometry.resolve(accessibility:logical,windowID:1,owner:42,
        records:[.init(id:1,owner:42,frame:animated)])==nil)
    #expect(WindowGeometry.resolve(accessibility:logical,windowID:1,owner:42,
        records:[.init(id:1,owner:42,frame:logical)])==logical)
}

@Test func exactWindowServerIdentityCorrectsAsideOnTV() {
    let stale=CGRect(x:0,y:0,width:1440,height:2539)
    let actual=CGRect(x:-1920,y:722,width:1440,height:2539)
    let frame=WindowGeometry.resolve(accessibility:stale,windowID:4392,owner:42,records:[
        .init(id:4392,owner:42,frame:actual),
        .init(id:5000,owner:42,frame:stale)])
    #expect(frame==actual)
}

@Test func windowGeometryNeverSubstitutesSiblingOrReusedWindowID() {
    let frame=CGRect(x:20,y:20,width:500,height:400)
    #expect(WindowGeometry.resolve(accessibility:frame,windowID:1,owner:42,records:[.init(id:2,owner:42,frame:frame)])==nil)
    #expect(WindowGeometry.resolve(accessibility:frame,windowID:1,owner:42,records:[.init(id:1,owner:99,frame:frame)])==nil)
    #expect(WindowGeometry.resolve(accessibility:frame,windowID:1,owner:42,records:[.init(id:1,owner:42,frame:frame),.init(id:1,owner:42,frame:frame)])==nil)
}

@Test func windowGeometryHandlesUnavailableMetadataWithoutFuzzyMatching() {
    let frame=CGRect(x:-700,y:-500,width:400,height:300)
    #expect(WindowGeometry.resolve(accessibility:frame,windowID:nil,owner:42,records:[])==frame)
    #expect(WindowGeometry.resolve(accessibility:frame,windowID:1,owner:42,records:nil)==frame)
    #expect(WindowGeometry.resolve(accessibility:nil,windowID:1,owner:42,records:[.init(id:1,owner:42,frame:frame)])==frame)
    #expect(WindowGeometry.resolve(accessibility:frame,windowID:1,owner:42,records:[.init(id:1,owner:42,frame:.null)])==nil)
    #expect(WindowGeometry.resolve(accessibility:.infinite,windowID:nil,owner:42,records:nil)==nil)
}
