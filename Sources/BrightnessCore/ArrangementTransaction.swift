import Foundation
import CoreGraphics

public protocol ArrangementDriver {
    func display(_ id:UInt32) async -> ArrangementDisplay?
    func read(_ id:String) async throws -> CGRect
    func write(_ id:String,frame:CGRect) async throws
}
public struct ArrangementUndo:Equatable {
    public struct Entry:Equatable {
        public let id:String,before:CGRect,after:CGRect
        public init(id:String,before:CGRect,after:CGRect){self.id=id;self.before=before;self.after=after}
    }
    public let display:ArrangementDisplay,entries:[Entry]
    public init(display:ArrangementDisplay,entries:[Entry]){self.display=display;self.entries=entries}
}
public struct ArrangementResult {
    public let undo:ArrangementUndo,message:String,complete:Bool
    public init(undo:ArrangementUndo,message:String,complete:Bool){self.undo=undo;self.message=message;self.complete=complete}
}
public struct ArrangementUndoResult {
    public let remaining:ArrangementUndo,message:String
    public init(remaining:ArrangementUndo,message:String){self.remaining=remaining;self.message=message}
}
public enum ArrangementTransaction {
    public static func apply(_ plan:ArrangementPlan,driver:any ArrangementDriver,
        pause:() async throws -> Void = {try await Task.sleep(nanoseconds:100_000_000)}) async -> ArrangementResult {
        var entries=[ArrangementUndo.Entry]()
        func result(_ complete:Bool,_ message:String)->ArrangementResult {
            .init(undo:.init(display:plan.display,entries:entries),message:message,complete:complete)
        }
        func checkDisplay() async throws {
            try Task.checkCancellation()
            guard await driver.display(plan.display.id)==plan.display else{throw TVError("Display setup changed. Refresh the preview.")}
        }
        do {
            try await checkDisplay()
            // Validate every original before the first side effect.
            for item in plan.items {
                guard ArrangementPlanner.near(try await driver.read(item.window.id),item.window.frame) else{throw TVError("A window changed. Refresh the preview before applying.")}
            }
            for item in plan.items {
                try await checkDisplay()
                let before=try await driver.read(item.window.id)
                guard ArrangementPlanner.near(before,item.window.frame) else{throw TVError("A window changed during arrangement. Remaining windows were left alone.")}
                if ArrangementPlanner.near(before,item.target){continue}
                var writeError:Error?
                do {try await driver.write(item.window.id,frame:item.target)} catch {writeError=error}
                var after:CGRect?
                var previousRead:CGRect?
                // Read back even when cancellation arrives after a write. Keep
                // Undo for observed changes; never issue a second write here.
                for _ in 0..<10 {
                    if let read=try? await driver.read(item.window.id) {
                        after=read
                        if ArrangementPlanner.near(read,item.target) || (previousRead==read && !ArrangementPlanner.near(read,before)){break}
                        previousRead=read
                    }
                    if Task.isCancelled{break}
                    do {try await pause()} catch {break}
                }
                if let after,!ArrangementPlanner.near(before,after) {
                    entries.append(.init(id:item.window.id,before:before,after:after))
                }
                try Task.checkCancellation()
                if let writeError{throw writeError}
                guard let after,item.zone.insetBy(dx:-2,dy:-2).contains(after),
                      abs(after.minX-item.target.minX)<=12,abs(after.minY-item.target.minY)<=12 else {
                    throw TVError("An app refused its zone. Undo this attempt or exclude that window and preview again.")
                }
            }
            return result(true,"Arranged \(plan.items.count) windows. Undo is available until these windows change.")
        } catch is CancellationError {return result(false,"Arrangement stopped. Undo can restore the verified changes.")}
        catch {return result(false,error.localizedDescription)}
    }
    public static func undo(_ journal:ArrangementUndo,driver:any ArrangementDriver,
        pause:() async throws -> Void = {try await Task.sleep(nanoseconds:100_000_000)}) async -> ArrangementUndoResult {
        func result(_ entries:[ArrangementUndo.Entry],_ message:String)->ArrangementUndoResult {
            .init(remaining:.init(display:journal.display,entries:entries),message:message)
        }
        guard await driver.display(journal.display.id)==journal.display else{return result(journal.entries,"Display setup changed. Undo left all windows alone.")}
        var restored=0,changed=0,remaining=journal.entries
        for entry in journal.entries.reversed() {
            if Task.isCancelled{break}
            guard await driver.display(journal.display.id)==journal.display else{break}
            do {
                let current=try await driver.read(entry.id)
                guard ArrangementPlanner.near(current,entry.after) else {
                    // Never reclaim a window the user has changed since Apply.
                    remaining.removeAll{$0.id==entry.id};changed+=1;continue
                }
                do {try await driver.write(entry.id,frame:entry.before)} catch { /* Read back a possibly partial write. */ }
                var observed:CGRect?
                for _ in 0..<10 {
                    if let frame=try? await driver.read(entry.id) {
                        observed=frame
                        if ArrangementPlanner.near(frame,entry.before,tolerance:12){break}
                    }
                    if Task.isCancelled{break}
                    do {try await pause()} catch {break}
                }
                if let observed,ArrangementPlanner.near(observed,entry.before,tolerance:12) {
                    restored+=1;remaining.removeAll{$0.id==entry.id}
                } else if let observed,let index=remaining.firstIndex(where:{$0.id==entry.id}) {
                    // Preserve recovery after a partial native resize, but a
                    // later Undo still requires this exact observed frame.
                    remaining[index] = .init(id:entry.id,before:entry.before,after:observed)
                }
            } catch { /* Unavailable exact identities remain guarded for a later retry. */ }
        }
        var message="Restored \(restored) windows."
        if changed>0{message+=" Left \(changed) manually changed windows alone."}
        if !remaining.isEmpty{message+=" \(remaining.count) could not be verified; Undo remains available."}
        return result(remaining,message)
    }
}
