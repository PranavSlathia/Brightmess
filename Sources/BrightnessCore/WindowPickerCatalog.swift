import Foundation

/// An immutable inventory snapshot: key assignments never change underneath a visible picker.
public struct WindowPickerCatalog {
    public struct Entry: Equatable {
        public let id: UUID, app: String, title: String
        public init(id: UUID, app: String, title: String) { self.id=id;self.app=app;self.title=title }
    }
    public struct Group: Equatable {
        public let key: String, name: String, entries: [Entry]
    }
    public let entries: [Entry]
    public init(_ entries: [Entry]) { self.entries=entries }
    public var groups: [Group] {
        var order=[String](), values=[String:[Entry]]()
        for entry in entries {
            let key=entry.app.first(where:{$0.isLetter}).map { String($0).uppercased() } ?? "#"
            if values[key] == nil { order.append(key) }
            values[key,default:[]].append(entry)
        }
        return order.map { key in
            let entries=values[key]!
            var names=[String]()
            for entry in entries where !names.contains(entry.app) { names.append(entry.app) }
            return Group(key:key,name:names.joined(separator:" / "),entries:entries)
        }
    }
}
