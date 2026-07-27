import Fluent
import FluentSQLiteDriver
import Testing
import Vapor
@testable import VaporPagination

@Suite("CursorPaginator integration (SQLite in-memory)")
struct CursorPaginatorIntegrationTests {
    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateTestUser())
        try await app.autoMigrate()
        return app
    }

    private func makeRequest(on app: Application, url: String) -> Request {
        Request(
            application: app,
            method: .GET,
            url: URI(string: url),
            on: app.eventLoopGroup.any()
        )
    }

    private func seed(_ db: any Database, _ count: Int) async throws {
        for i in 1...count {
            let u = TestUser(name: "user-\(i)")
            try await u.create(on: db)
        }
    }

    @Test
    func firstPageReturnsItemsAndHasMore() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.autoRevert() } }
        let db = app.db
        try await seed(db, 5)

        let request = makeRequest(on: app, url: "/users")
        let page: CursorPaginator<TestUser> = try await TestUser.query(on: db)
            .sort(\.$id)
            .cursorPaginate(perPage: 2, on: request)

        #expect(page.items.count == 2)
        #expect(page.hasMore == true)
        #expect(page.onFirstPage == true)
        #expect(page.cursor == nil)
        #expect(page.nextPageUrl() != nil)
        #expect(page.previousPageUrl() == nil)
    }

    @Test
    func nextPageLoadsFollowingItems() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.autoRevert() } }
        let db = app.db
        try await seed(db, 5)

        // First page.
        let firstReq = makeRequest(on: app, url: "/users")
        let first: CursorPaginator<TestUser> = try await TestUser.query(on: db)
            .sort(\.$id)
            .cursorPaginate(perPage: 2, on: firstReq)
        let nextCursor = first.nextCursor()
        #expect(nextCursor != nil)
        let encoded = nextCursor!.encoded()

        // Second page using the next URL.
        let nextReq = makeRequest(on: app, url: "/users?cursor=\(encoded)")
        let second: CursorPaginator<TestUser> = try await TestUser.query(on: db)
            .sort(\.$id)
            .cursorPaginate(perPage: 2, on: nextReq)
        #expect(second.items.count == 2)
        #expect(second.cursor?.points == .next)
        #expect(second.items.first?.id != first.items.first?.id)
        #expect(second.hasMore == true)
    }

    @Test
    func lastPageReportsNoMore() async throws {
        let app = try await makeApp()
        defer { Task { try? await app.autoRevert() } }
        let db = app.db
        try await seed(db, 3)

        let request = makeRequest(on: app, url: "/users")
        let page: CursorPaginator<TestUser> = try await TestUser.query(on: db)
            .sort(\.$id)
            .cursorPaginate(perPage: 10, on: request)
        #expect(page.items.count == 3)
        #expect(page.hasMore == false)
        #expect(page.onLastPage == true)
        #expect(page.nextPageUrl() == nil)
    }
}