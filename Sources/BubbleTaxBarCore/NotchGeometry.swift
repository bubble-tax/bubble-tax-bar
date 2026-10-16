import CoreGraphics
import Foundation

/// All coordinates are AppKit global screen points, including secondary displays.
public struct NotchGeometry {
    public let compact: CGRect
    public let notchWidth: CGFloat
    public let wingWidth: CGFloat

    public static func make(screen: CGRect, left: CGRect, right: CGRect, topInset: CGFloat) -> Self? {
        let notchWidth = right.minX - left.maxX
        guard topInset.isFinite, topInset > 0, topInset < screen.height / 4,
              notchWidth.isFinite, notchWidth > 0,
              left.minX >= screen.minX, right.maxX <= screen.maxX,
              left.maxX < screen.maxX, right.minX > screen.minX else { return nil }
        let wing = min(CGFloat(140), left.width, right.width)
        guard wing >= 80 else { return nil }
        return Self(compact: CGRect(x: left.maxX - wing, y: screen.maxY - topInset,
                                    width: notchWidth + wing * 2, height: topInset),
                    notchWidth: notchWidth, wingWidth: wing)
    }
}
