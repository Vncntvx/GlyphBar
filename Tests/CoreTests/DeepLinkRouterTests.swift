import XCTest
@testable import GlyphBar

final class DeepLinkRouterTests: XCTestCase {
    func testParsesModuleDeepLinks() {
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/clock")!), .module("clock"))
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/clock/settings")!), .moduleSettings("clock"))
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/counter/action/increment")!), .moduleAction(moduleID: "counter", actionID: "increment"))
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://module/network-mock/action/retry")!), .moduleAction(moduleID: "networkMock", actionID: "retry"))
    }

    func testParsesAppDeepLinks() {
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/settings")!), .appSettings)
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/modules")!), .appModules)
        XCTAssertEqual(DeepLinkRouter.parse(URL(string: "glyphbar://app/logs")!), .appLogs)
    }

    func testRejectsInvalidLinks() {
        XCTAssertNil(DeepLinkRouter.parse(URL(string: "https://module/clock")!))
        XCTAssertNil(DeepLinkRouter.parse(URL(string: "glyphbar://module")!))
        XCTAssertNil(DeepLinkRouter.parse(URL(string: "glyphbar://app/unknown")!))
    }
}
