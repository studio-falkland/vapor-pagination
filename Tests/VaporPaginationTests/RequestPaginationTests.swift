import Foundation
import HTTPTypes
import Testing
import Vapor
@testable import VaporPagination

struct RequestPaginationTests {
    private func makeRequest(
        url: String,
        hostHeader: String? = nil,
        localAddress: SocketAddress? = nil
    ) -> Request {
        var headers = HTTPFields()
        if let hostHeader { headers[HTTPField.Name("Host")!] = hostHeader }
        return Request(
            method: .get,
            url: URI(string: url),
            headers: headers,
            localAddress: localAddress
        )
    }

    @Test
    func paginationPathUsesBaseURL() {
        let req = makeRequest(url: "/users")
        let baseURL = URL(string: "http://api.example.com")!
        #expect(req.paginationPath(baseURL: baseURL) == "http://api.example.com/users")
    }

    @Test
    func paginationPathHonorsHostHeader() {
        let req = makeRequest(url: "/users", hostHeader: "real.example.com:9000")
        #expect(req.paginationPath() == "http://real.example.com:9000/users")
    }

    @Test
    func paginationPathFallsBackToLocalAddress() {
        let req = makeRequest(url: "/users", localAddress: .ipv4(host: "127.0.0.1", port: 8080))
        #expect(req.paginationPath() == "http://127.0.0.1:8080/users")
    }

    @Test
    func appendedQueryExcludesCursor() {
        let req = makeRequest(url: "/users?cursor=abc&sort=name")
        let result = req.appendedQuery(excluding: "cursor")
        #expect(result["cursor"] == nil)
        #expect(result["sort"] == "name")
    }

    @Test
    func appendedQueryReturnsEmptyForNoQuery() {
        let req = makeRequest(url: "/users")
        #expect(req.appendedQuery(excluding: "cursor") == [:])
    }

    @Test
    func appendedQueryDecodesPercentEncoding() {
        let req = makeRequest(url: "/users?filter=hello%20world")
        let result = req.appendedQuery(excluding: "cursor")
        #expect(result["filter"] == "hello world")
    }
}
