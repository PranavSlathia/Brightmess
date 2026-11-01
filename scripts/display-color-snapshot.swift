import AppKit
import CoreGraphics
import Foundation

var rows: [[String: Any]] = []
for screen in NSScreen.screens {
    guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
    let capacity = CGDisplayGammaTableCapacity(id)
    var r = [CGGammaValue](repeating: 0, count: Int(capacity)), g = r, b = r
    var count: UInt32 = 0
    let error = CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count)
    rows.append(["name": screen.localizedName, "id": id, "rotation": CGDisplayRotation(id),
                 "error": error.rawValue, "samples": count,
                 "peaks": [r.max() ?? 0, g.max() ?? 0, b.max() ?? 0]])
}
print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
