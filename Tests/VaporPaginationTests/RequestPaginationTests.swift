import Testing
import Vapor
import VaporUtilities
@testable import VaporPagination

struct RequestPaginationTests {
    private func makeRequest(
        url: String,
        host: String = "127.0.0.1",
        port: Int = 8080,
        hostHeader: String? = nil
    ) -> Request {
        let app = Application(.testing)
        app.http.server.configuration.hostname = host
        app.http.server.configuration.port = port
        var headers = HTTPHeaders()
        if let h = hostHeader { headers.add(name: "Host", value: h) }
        let req = Request(
            application: app,
            method: .GET,
            url: URI(string: url),
            headers: headers,
            on: app.eventLoopGroup.any()
        )
        return req
    }

    @Test
    func paginationPathUsesServerHostname() {
        let req = makeRequest(url: "/users", host: "api.example.com")
        #expect(req.paginationPath == "http://api.example.com/users")
    }

    @Test
    func paginationPathHonorsHostHeader() {
        let req = makeRequest(url: "/users", hostHeader: "real.example.com:9000")
        #expect(req.paginationPath == "http://real.example.com:9000/users")
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
