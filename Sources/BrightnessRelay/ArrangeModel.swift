import AppKit
import BrightnessCore

@MainActor final class ArrangeModel:ObservableObject {
    enum Stage {case closed,loading,preview,applying,result}
    @Published var stage=Stage.closed
    @Published var windows=[ArrangementWindow]()
    @Published var selected=Set<String>()
    @Published var mode=ArrangementMode.smart
    @Published var plan:ArrangementPlan?
    @Published var message=""
    @Published var showWindows=false
    private(set) var display:ArrangementDisplay?
    private(set) var journal:ArrangementUndo?
    let port:any ArrangePort
    private var task:Task<Void,Never>?,ticket=UUID()
    var changed:(()->Void)?
    var working:Bool {stage == .applying}
    var canUndo:Bool {journal?.entries.isEmpty == false && journal?.display.id==display?.id && !working}
    init(port:(any ArrangePort)?=nil){self.port=port ?? ArrangeNativePort()}
    func open(_ display:ArrangementDisplay){self.display=display;showWindows=false;refresh()}
    func toggleWindows(){showWindows.toggle();changed?()}
    func refresh() {
        guard !working,let display else{return}
        task?.cancel();ticket=UUID();let request=ticket;stage = .loading;message="Finding normal windows on this desktop…";plan=nil;changed?()
        task=Task{[weak self] in
            guard let self else{return}
            do {
                guard let current=await port.display(display.id) else{throw TVError("That display disconnected. Close and reopen on the intended screen.")}
                guard !Task.isCancelled,ticket==request else{return}
                self.display=current
                let values=try await port.capture(current)
                guard !Task.isCancelled,ticket==request else{return}
                windows=values;selected=Set(values.map(\.id));stage = .preview;replan()
            }catch {guard ticket==request else{return};stage = .preview;windows=[];selected=[];message=error.localizedDescription;changed?()}
        }
    }
    func choose(_ mode:ArrangementMode){guard !working else{return};self.mode=mode;replan()}
    func include(_ id:String,_ on:Bool){guard !working else{return};if on{selected.insert(id)}else{selected.remove(id)};replan()}
    func selectAll(_ on:Bool){guard stage == .preview else{return};selected=on ? Set(windows.map(\.id)):[];replan()}
    func replan(){
        guard let display else{return}
        let chosen=windows.filter{selected.contains($0.id)}
        plan=ArrangementPlanner.plan(windows:chosen,display:display,mode:mode)
        if windows.isEmpty {message="No normal windows here. Full-screen, minimized and other-desktop windows stay untouched."}
        else if chosen.isEmpty {message="Select at least one window to preview."}
        else if chosen.count>16 {message="Select 16 or fewer windows for one arrangement."}
        else if plan == nil {message="These windows cannot fit without overlap. Exclude a window or try another layout."}
        else {message="Preview only · \(chosen.count) windows · other displays stay untouched."}
        changed?()
    }
    func apply(){
        guard !working,let plan else{return}
        ticket=UUID();let request=ticket;stage = .applying;message="Arranging selected windows…";changed?()
        task=Task{[weak self] in
            guard let self else{return}
            let result=await ArrangementTransaction.apply(plan,driver:port)
            guard ticket==request else{return}
            journal=result.undo;message=result.message;stage = .result;changed?()
        }
    }
    func undo(){
        guard canUndo,let journal else{return};stage = .applying;message="Restoring unchanged windows…";changed?()
        task=Task{[weak self] in
            guard let self else{return}
            let result=await ArrangementTransaction.undo(journal,driver:port)
            message=result.message;self.journal=result.remaining;stage = .result;changed?()
        }
    }
    func close(){
        if working {task?.cancel();message="Stopping after the current window…";changed?();return}
        task?.cancel();ticket=UUID();stage = .closed;plan=nil;windows=[];selected=[];changed?()
    }
    func topologyChanged(){
        if working {task?.cancel()} else if stage != .closed {plan=nil;message="Display setup changed. Close and reopen on the intended screen.";changed?()}
    }
    #if DEBUG
    func finish()async{await task?.value}
    #endif
}
