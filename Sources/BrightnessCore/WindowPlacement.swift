import CoreGraphics

public enum WindowPlacement {
    /// The source is the window's screen, never the pointer or the status item's screen.
    public static func otherDisplay(containing source: UInt32, connected: [UInt32]) -> UInt32? {
        guard connected.count == 2, connected.contains(source) else { return nil }
        return connected.first { $0 != source }
    }
    public struct Snapshot {
        public let screen: UInt32, rect: CGRect, usable: CGRect, fullScreen: Bool, movable: Bool
        public init(screen: UInt32, rect: CGRect, usable: CGRect, fullScreen: Bool, movable: Bool) {
            self.screen = screen; self.rect = rect; self.usable = usable
            self.fullScreen = fullScreen; self.movable = movable
        }
    }
    /// The read and write closures must be bound to the original AX element, never to current focus.
    public static func move(original: UInt32, destination: UInt32?, trusted: Bool,
                            usable: (UInt32) -> CGRect?, read: () -> Snapshot?,
                            write: (CGRect) -> Bool) throws {
        guard trusted else { throw TVError("Enable Accessibility to move windows.") }
        guard let destination, let target = usable(destination) else { throw TVError("Destination screen is no longer connected.") }
        guard let window = read() else { throw TVError("That window closed or is no longer available.") }
        guard window.screen != destination else { throw TVError("Window is already on this screen.") }
        guard window.screen == original else { throw TVError("Window moved since you opened Light desk. Choose it again.") }
        guard !window.fullScreen else { throw TVError("Exit full screen first, then move this window.") }
        guard window.movable else { throw TVError("This app does not allow moving this window.") }
        guard write(fit(window.rect,from:window.usable,to:target)),
              read()?.screen == destination else { throw TVError("The app did not move the window to the requested screen.") }
    }
    /// All three rectangles are in global, top-left-origin accessibility points.
    public static func fit(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        if abs(window.minX-source.minX) <= 4 && abs(window.minY-source.minY) <= 4 &&
            abs(window.width-source.width) <= 4 && abs(window.height-source.height) <= 4 { return target }
        let w = min(window.width,target.width), h = min(window.height,target.height)
        func fraction(_ delta: CGFloat, _ room: CGFloat) -> CGFloat {
            room > 0 ? max(0,min(1,delta/room)) : 0.5
        }
        return CGRect(x: target.minX + (target.width-w)*fraction(window.minX-source.minX,source.width-window.width),
                      y: target.minY + (target.height-h)*fraction(window.minY-source.minY,source.height-window.height),
                      width: w, height: h)
    }
}
