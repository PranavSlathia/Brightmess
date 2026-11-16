import Foundation

/// Panel-local policy. Never queues a command while loading, repeats a write,
/// consumes Tab/Space, or handles another window's keyboard events.
public struct ArrangeKeyRouter {
    public enum Phase {case closed,loading,preview,applying,result}
    public enum Action:Equatable {case pass,consume,apply,close,smart,equal,windows,undo}
    public struct Modifiers:OptionSet,Sendable {
        public let rawValue:Int
        public init(rawValue:Int){self.rawValue=rawValue}
        public static let command=Self(rawValue:1),option=Self(rawValue:2),control=Self(rawValue:4),shift=Self(rawValue:8)
    }
    public private(set) var armed=false
    public init() {}
    public mutating func opened(modifiers:Modifiers){armed=modifiers.isEmpty}
    public mutating func flagsChanged(_ modifiers:Modifiers){if modifiers.isEmpty {armed=true}}
    public mutating func route(key:String,modifiers:Modifiers,repeating:Bool,isKeyWindow:Bool,
        phase:Phase,canApply:Bool,canUndo:Bool,hasWindows:Bool,editingText:Bool=false)->Action {
        guard isKeyWindow,phase != .closed else{return .pass}
        flagsChanged(modifiers)
        guard !editingText else{return .pass}
        let key=key.lowercased(),plain=modifiers.isEmpty
        let known=(plain && ["return","enter","escape","s","e","w"].contains(key)) || (modifiers == .command && key=="z")
        guard known else{return .pass}
        guard armed,!repeating else{return .consume}
        if key=="escape" {return .close}
        if modifiers == .command {return canUndo ? .undo:.consume}
        if key=="return" || key=="enter" {
            if phase == .result{return .close}
            return phase == .preview && canApply ? .apply:.consume
        }
        guard phase == .preview,hasWindows else{return .consume}
        return key=="s" ? .smart:key=="e" ? .equal:.windows
    }
}
