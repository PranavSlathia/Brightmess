import AppKit
import BrightnessCore

@MainActor final class BringHereModel {
    enum Stage:Equatable {case closed,loading,apps,group(String),search,working,problem(String)}
    struct Row {let key:String,app:String,detail:String,windows:[DeskWindow]}
    let port:any WindowRetrievalPort
    private(set) var stage=Stage.closed,destination:UInt32?
    private(set) var entries=[DeskWindow](),selected=0,query="",progress="",notice=""
    private(set) var successfulMoves=0
    var changed:(()->Void)?,succeeded:((DeskWindow)->Void)?
    private var task:Task<Void,Never>?,ticket=UUID()
    init(port:(any WindowRetrievalPort)?=nil){self.port=port ?? MacWindowDesk()}
    var visible:Bool {stage != .closed}
    var working:Bool {stage == .working}
    var title:String {"Bring to "+(port.screens.first{$0.id==destination}.map{friendly($0.name)} ?? "display")}
    private func friendly(_ name:String)->String {name=="Beyond TV" ? "TV":name}
    var subtitle:String {
        if case .group(let key)=stage {return key+" · choose a window"}
        return "From "+port.screens.filter{$0.id != destination}.map{friendly($0.name)}.joined(separator:", ")+" · choose a window"
    }
    var rows:[Row] {
        let catalog=WindowPickerCatalog(entries.map{.init(id:$0.id,app:$0.app,title:$0.displayTitle)})
        func detail(_ window:DeskWindow)->String {
            switch window.retrievalState {
            case .normal:return window.displayTitle
            case .fullScreen:return window.displayTitle+" · Full screen, exits to move"
            case .blocked(let reason):return reason
            }
        }
        switch stage {
        case .apps:
            return catalog.groups.map { group in
                let windows=group.entries.compactMap{entry in entries.first{$0.id==entry.id}}
                return Row(key:group.key,app:group.name,detail:windows.count==1 ? detail(windows[0]):"\(windows.count) windows",windows:windows)
            }
        case .group(let key):
            let group=catalog.groups.first{$0.key==key}
            return (group?.entries ?? []).enumerated().compactMap { index,entry in
                guard let window=entries.first(where:{$0.id==entry.id}) else{return nil}
                return Row(key:index<9 ? String(index+1):"",app:window.app,detail:detail(window),windows:[window])
            }
        case .search:
            return entries.filter{query.isEmpty || ($0.app+" "+$0.displayTitle).localizedCaseInsensitiveContains(query)}.map{
                Row(key:"",app:$0.app,detail:detail($0),windows:[$0])
            }
        default:return []
        }
    }
    func open(destination:UInt32?) {self.destination=destination;refresh()}
    func refresh() {
        guard !working else{return}
        task?.cancel();ticket=UUID();let request=ticket
        entries=[];selected=0;query="";notice="";progress=""
        guard port.trusted else{stage = .problem("Enable Accessibility to list and move windows.");changed?();return}
        let screens=port.screens
        guard let dest=destination,screens.contains(where:{$0.id==dest}) else{
            stage = .problem("Destination disconnected. Reopen on a connected screen.");changed?();return
        }
        guard screens.count>1 else{stage = .problem("Connect another Mac display to bring windows here.");changed?();return}
        stage = .loading;changed?()
        task=Task { [weak self] in
            guard let self else{return}
            let entries=await port.retrievalInventory(excluding:dest,screens:screens)
            guard !Task.isCancelled,ticket==request,visible else{return}
            guard port.trusted,port.screens.map(\.id)==screens.map(\.id) else{
                stage = .problem("Permission or displays changed. Refresh the choices.");changed?();return
            }
            self.entries=entries;stage = .apps;changed?()
        }
    }
    func close() {
        ticket=UUID();task?.cancel();task=nil;stage = .closed
        entries=[];query="";notice="";progress="";destination=nil;changed?()
    }
    func topologyChanged() {
        guard visible else{return}
        task?.cancel();ticket=UUID();entries=[]
        stage = .problem("Display setup changed. Reopen the picker on a connected screen.");changed?()
    }
    func changeDestination(_ delta:Int) {
        guard !working,stage != .search else{return}
        let screens=port.screens.sorted{$0.frame.minX<$1.frame.minX}
        guard screens.count>1,let index=screens.firstIndex(where:{$0.id==destination}) else{return}
        destination=screens[(index+delta+screens.count)%screens.count].id;refresh()
    }
    func search(_ text:String){guard stage == .search else{return};query=text;selected=0;changed?()}
    func handlesKey(_ key:String)->Bool {
        if key=="escape" {return true}
        switch stage {
        case .apps,.group:
            return ["left","right","up","down","tab","backtab","return"].contains(key) ||
                (stage == .apps && key=="/") || rows.contains{$0.key==key.uppercased() && !$0.key.isEmpty}
        case .search:return ["up","down","tab","backtab","return"].contains(key)
        default:return false
        }
    }
    func key(_ key:String) {
        if key=="escape" {
            switch stage {
            case .group,.search:stage = .apps;query="";notice="";selected=0;changed?()
            default:close()
            };return
        }
        guard stage == .apps || stage == .search || {if case .group=stage{return true};return false}() else{return}
        if key=="left" || key=="right" {changeDestination(key=="left" ? -1:1);return}
        if ["up","down","tab","backtab"].contains(key) {
            guard !rows.isEmpty else{return};selected=(selected+(["down","tab"].contains(key) ? 1:rows.count-1))%rows.count;changed?();return
        }
        if key=="return" {select(selected);return}
        if key=="/",stage == .apps {stage = .search;query="";selected=0;changed?();return}
        if stage != .search,let index=rows.firstIndex(where:{$0.key==key.uppercased() && !$0.key.isEmpty}) {select(index)}
    }
    func select(_ index:Int) {
        let list=rows
        guard !working,list.indices.contains(index),let dest=destination else{return}
        let row=list[index]
        if row.windows.count>1 {stage = .group(row.key);selected=0;notice="";changed?();return}
        guard let window=row.windows.first,entries.contains(where:{$0.id==window.id}) else{return}
        if case .blocked(let reason)=window.retrievalState {notice=reason;changed?();return}
        task?.cancel();ticket=UUID();let request=ticket
        stage = .working;progress="Checking window…";notice="";changed?()
        task=Task { [weak self] in
            guard let self else{return}
            do {
                try await port.retrieve(window,to:dest){[weak self] text in
                    guard let self,self.ticket==request else{return};self.progress=text;self.changed?()
                }
                guard !Task.isCancelled,ticket==request else{return}
                successfulMoves+=1;succeeded?(window);close()
            } catch {
                guard !Task.isCancelled,ticket==request else{return}
                stage = .problem(error.localizedDescription);entries=[];changed?()
            }
        }
    }
    var diagnostics:[String:Any] {
        ["visible":visible,"working":working,"moves":successfulMoves,"windowCount":entries.count,"accessibility":port.trusted]
    }
    #if DEBUG
    func finish() async {await task?.value}
    #endif
}
