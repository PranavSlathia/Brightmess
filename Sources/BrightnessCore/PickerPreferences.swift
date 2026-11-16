import Foundation

public struct PinnedApplication: Codable, Equatable, Identifiable, Sendable {
    public let id: String, name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
    public static let defaults: [Self] = [
        .init(id:"at.studio.AsideBrowser",name:"Aside"), .init(id:"com.openai.codex",name:"Codex"),
        .init(id:"com.apple.Terminal",name:"Terminal"), .init(id:"app.zen-browser.zen",name:"Zen"),
        .init(id:"com.apple.finder",name:"Finder")
    ]
}
/// No titles or persistent history. Process birth prevents PID reuse.
public struct RecentWindowIdentity: Hashable, Sendable {
    public let process: Int32, startedAt: Double, window: UInt32
    public init(process: Int32, startedAt: Double, window: UInt32) {
        self.process=process; self.startedAt=startedAt; self.window=window
    }
}
public struct RecentWindowHistory: Sendable {
    public private(set) var entries: [RecentWindowIdentity] = []
    public init() {}
    public mutating func record(_ identity: RecentWindowIdentity) {
        entries.removeAll { $0 == identity }; entries.insert(identity, at:0)
        entries = Array(entries.prefix(20))
    }
    public mutating func discardExitedProcesses(_ alive: Set<Int32>) {
        entries.removeAll { !alive.contains($0.process) }
    }
}
public enum PickerOrdering {
    public struct Item {
        public let id: UUID, app: String, title: String, bundleID: String?, identity: RecentWindowIdentity?
        public init(id:UUID, app:String, title:String, bundleID:String?, identity:RecentWindowIdentity?) {
            self.id=id; self.app=app; self.title=title; self.bundleID=bundleID; self.identity=identity
        }
    }
    public static func ordered(_ items: [Item], pins:[PinnedApplication], recent:[RecentWindowIdentity]) -> [UUID] {
        let pinRanks=Dictionary(pins.enumerated().map{($0.element.id,$0.offset)},uniquingKeysWith:min)
        let recentRanks=Dictionary(recent.enumerated().map{($0.element,$0.offset)},uniquingKeysWith:min)
        func rank(_ item:Item) -> (Int,Int) {
            (item.bundleID.flatMap{pinRanks[$0]} ?? Int.max,
             item.identity.flatMap{recentRanks[$0]} ?? Int.max)
        }
        func appKey(_ item:Item)->String {item.bundleID.map{"bundle:"+$0} ?? "name:"+item.app}
        var appRanks=[String:(Int,Int)]()
        for item in items {
            let key=appKey(item),value=rank(item)
            if let old=appRanks[key] {appRanks[key]=old < value ? old:value} else{appRanks[key]=value}
        }
        return items.enumerated().sorted { l,r in
            let a=appRanks[appKey(l.element)]!,b=appRanks[appKey(r.element)]!
            if a != b { return a < b }
            if l.element.app != r.element.app { return l.element.app.localizedStandardCompare(r.element.app) == .orderedAscending }
            let x=rank(l.element).1,y=rank(r.element).1
            if x != y { return x < y }
            if l.element.title != r.element.title { return l.element.title.localizedStandardCompare(r.element.title) == .orderedAscending }
            return l.offset < r.offset
        }.map { $0.element.id }
    }
}
