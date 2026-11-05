import Foundation
import CoreGraphics

/// Narrow transactional boundary. Every adapter is bound to the original window,
/// never current focus. Waiting happens only during an explicitly requested move.
public enum WindowRetrieval {
    public enum ReadError:Error {case temporarilyUnavailable}
    public struct Snapshot {
        public let screen:UInt32, rect:CGRect, usable:CGRect, fullFrame:CGRect
        public let fullScreen:Bool, canExitFullScreen:Bool, movable:Bool
        public init(screen:UInt32,rect:CGRect,usable:CGRect,fullFrame:CGRect,fullScreen:Bool,canExitFullScreen:Bool,movable:Bool) {
            self.screen=screen;self.rect=rect;self.usable=usable;self.fullFrame=fullFrame
            self.fullScreen=fullScreen;self.canExitFullScreen=canExitFullScreen;self.movable=movable
        }
    }
    public static func coversDisplay(_ window:CGRect,_ display:CGRect)->Bool {
        abs(window.minX-display.minX)<=8 && abs(window.width-display.width)<=8 &&
        abs(window.minY-display.minY)<=40 && abs(window.maxY-display.maxY)<=8
    }
    public static func run(original:UInt32,destination:UInt32,
        read:() async throws -> Snapshot,
        target:() async throws -> CGRect,
        exitFullScreen:() async throws -> Void,
        write:(CGRect) async throws -> Void,
        pause:() async throws -> Void = {try await Task.sleep(nanoseconds:100_000_000)},
        now:() -> TimeInterval = {ProcessInfo.processInfo.systemUptime},
        progress:(String) async -> Void = {_ in}) async throws {
        func stableRead() async throws -> Snapshot {
            let deadline=now()+1
            for _ in 0..<10 {
                try Task.checkCancellation();_ = try await target()
                do {return try await read()}
                catch ReadError.temporarilyUnavailable {
                    guard now()<deadline else{break}
                    try await pause()
                }
            }
            throw TVError("The window's position is temporarily unavailable. Wait a moment and refresh the choices.")
        }
        try Task.checkCancellation()
        _ = try await target()
        var value=try await stableRead()
        guard value.screen != destination else {throw TVError("This window is already here. Refresh the choices.")}
        guard value.screen == original else {throw TVError("This window moved since the picker opened. Refresh the choices.")}
        let startedFullScreen=value.fullScreen
        if startedFullScreen {
            guard value.canExitFullScreen, coversDisplay(value.rect,value.fullFrame) else {
                throw TVError("This full-screen or Split View window cannot be safely retrieved. Exit full screen first.")
            }
            await progress("Leaving full screen…")
            try Task.checkCancellation();_ = try await target()
            let beforeExit=try await stableRead()
            guard beforeExit.screen==original,beforeExit.fullScreen,beforeExit.canExitFullScreen,
                  coversDisplay(beforeExit.rect,beforeExit.fullFrame) else {
                throw TVError("The full-screen window changed. No exit request was sent.")
            }
            try Task.checkCancellation();try await exitFullScreen()
            var settled=false
            var settledFrame:CGRect?
            var settledSince:TimeInterval?
            let deadline=now()+8
            for _ in 0..<80 {
                guard now()<deadline else{break}
                try Task.checkCancellation();_ = try await target()
                do {value=try await read()}
                catch ReadError.temporarilyUnavailable {
                    settledFrame=nil;settledSince=nil;try await pause();continue
                }
                guard value.screen==original else {throw TVError("The window changed displays while leaving full screen. No move was sent.")}
                if !value.fullScreen && value.movable {
                    if settledFrame==value.rect,let since=settledSince,now()-since>=0.3 {settled=true;break}
                    if settledFrame != value.rect {settledSince=now();settledFrame=value.rect}
                } else {settledFrame=nil;settledSince=nil}
                try await pause()
            }
            guard settled else {throw TVError("The app did not finish leaving full screen. No move was sent.")}
        }
        try Task.checkCancellation()
        _ = try await target();value=try await stableRead()
        guard value.screen==original,!value.fullScreen,value.movable else {
            throw TVError(startedFullScreen ? "The window left full screen but is not ready to move. Try again." : "This window changed or does not allow movement. Refresh the choices.")
        }
        await progress("Bringing window here…")
        value=try await stableRead();let destinationFrame=try await target()
        guard value.screen==original,!value.fullScreen,value.movable else {
            throw TVError("The window changed before the move. Refresh the choices.")
        }
        let fitted=WindowPlacement.fit(value.rect,from:value.usable,to:destinationFrame)
        try Task.checkCancellation();try await write(fitted)
        let deadline=now()+2
        var confirmedFrame:CGRect?,confirmedSince:TimeInterval?
        for _ in 0..<20 {
            guard now()<deadline else{break}
            try Task.checkCancellation();_ = try await target()
            let result:Snapshot
            do {result=try await read()}
            catch ReadError.temporarilyUnavailable {confirmedFrame=nil;confirmedSince=nil;try await pause();continue}
            if result.screen==destination && !result.fullScreen {
                if confirmedFrame==result.rect,let since=confirmedSince,now()-since>=0.2 {return}
                if confirmedFrame != result.rect {confirmedFrame=result.rect;confirmedSince=now()}
            } else {confirmedFrame=nil;confirmedSince=nil}
            try await pause()
        }
        throw TVError("The app did not confirm the requested display. Check the window and refresh.")
    }
}
