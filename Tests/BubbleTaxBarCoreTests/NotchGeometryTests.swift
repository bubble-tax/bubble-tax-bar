import CoreGraphics
import XCTest
@testable import BubbleTaxBarCore

final class NotchGeometryTests: XCTestCase {
    func testBuiltInScreenUsesActualCameraGap() throws {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let result = try XCTUnwrap(NotchGeometry.make(screen: screen,
            left: CGRect(x: 0, y: 950, width: 666, height: 32),
            right: CGRect(x: 846, y: 950, width: 666, height: 32), topInset: 32))
        XCTAssertEqual(result.notchWidth, 180)
        XCTAssertEqual(result.compact, CGRect(x: 526, y: 950, width: 460, height: 32))
    }
    func testSecondaryScreenUsesGlobalOrigin() throws {
        let result = try XCTUnwrap(NotchGeometry.make(screen: CGRect(x: -1512, y: 500, width: 1512, height: 982),
            left: CGRect(x: -1512, y: 1450, width: 666, height: 32),
            right: CGRect(x: -666, y: 1450, width: 666, height: 32), topInset: 32))
        XCTAssertEqual(result.compact.minX, -986)
        XCTAssertEqual(result.compact.maxY, 1482)
    }
    func testNonNotchedOrInvalidScreenIsRejected() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let left = CGRect(x: 0, y: 768, width: 410, height: 32)
        let right = CGRect(x: 590, y: 768, width: 410, height: 32)
        XCTAssertNil(NotchGeometry.make(screen: screen, left: left, right: right, topInset: 0))
        XCTAssertNil(NotchGeometry.make(screen: screen, left: right, right: left, topInset: 32))
        XCTAssertNil(NotchGeometry.make(screen: screen, left: left, right: right, topInset: .infinity))
    }
}
