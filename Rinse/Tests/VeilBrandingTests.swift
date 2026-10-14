import XCTest
import UIKit
@testable import Rinse

final class VeilBrandingTests: XCTestCase {
    func testVeilInstalledIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.billy.veil")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Veil")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "Veil")
        XCTAssertNotNil(UIImage(named: "Brand"))
    }
    func testVeilAccentIsGreenInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let color = UIColor(RinseTheme.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            XCTAssertGreaterThan(g, b)
            XCTAssertGreaterThan(b, r)
            XCTAssertEqual(a, 1, accuracy: 0.001)
        }
    }
}
