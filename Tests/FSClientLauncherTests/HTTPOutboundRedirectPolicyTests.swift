import Foundation
import XCTest

@testable import FSClientLauncherLib

final class HTTPOutboundRedirectPolicyTests: XCTestCase {
    func testFollowsHttpRedirectWithHost() {
        let next = URL(string: "https://example.com/path")!
        let req = URLRequest(url: next)
        let prev = URL(string: "https://origin.example/")!
        let resp = HTTPURLResponse(url: prev, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var out: URLRequest?
        HTTPOutboundRedirectPolicy.respondToRedirect(context: "test", response: resp, newRequest: req) { out = $0 }
        XCTAssertNotNil(out)
        XCTAssertEqual(out?.url?.absoluteString, next.absoluteString)
    }

    func testRejectsFsClientLauncherRedirect() {
        let next = URL(string: "fsclientlauncher:launch?broker=https%3A%2F%2Fx")!
        let req = URLRequest(url: next)
        let prev = URL(string: "https://server/app/api/fsclient")!
        let resp = HTTPURLResponse(url: prev, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var out: URLRequest?
        HTTPOutboundRedirectPolicy.respondToRedirect(context: "test", response: resp, newRequest: req) { out = $0 }
        XCTAssertNil(out)
    }

    func testRejectsNonHttpRedirect() {
        let next = URL(string: "ftp://files.example/pub")!
        let req = URLRequest(url: next)
        let prev = URL(string: "https://a/")!
        let resp = HTTPURLResponse(url: prev, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: nil)!
        var out: URLRequest?
        HTTPOutboundRedirectPolicy.respondToRedirect(context: "test", response: resp, newRequest: req) { out = $0 }
        XCTAssertNil(out)
    }
}
