import XCTest
@testable import Pastie

final class ProjectLinksTests: XCTestCase {
    func testSourceRepositoryPointsAtGitHub() {
        XCTAssertEqual(ProjectLinks.sourceRepository.host, "github.com")
        XCTAssertEqual(ProjectLinks.sourceRepository.path, "/Stav-Sananes/Pastie")
    }

    func testIssuesLiveUnderTheRepository() {
        XCTAssertEqual(ProjectLinks.issues.path, "/Stav-Sananes/Pastie/issues")
    }

    func testBuyMeACoffeeIsTheAuthorsPage() {
        XCTAssertEqual(ProjectLinks.buyMeACoffee.host, "buymeacoffee.com")
        XCTAssertEqual(ProjectLinks.buyMeACoffee.path, "/stav_sananes")
    }

    func testEveryLinkIsHTTPS() {
        for url in [ProjectLinks.sourceRepository, ProjectLinks.issues, ProjectLinks.buyMeACoffee, ProjectLinks.licence] {
            XCTAssertEqual(url.scheme, "https", "\(url) must be https")
        }
    }

    func testVersionReadsTheBundleOrSaysUnknown() {
        let bundled = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(ProjectLinks.version, bundled ?? "unknown")
    }
}
