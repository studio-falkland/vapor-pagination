import FluentKit
import FluentSQLiteDriver
import Logging
import NIOPosix
import Testing
import Vapor
@testable import VaporPagination

@Suite("CursorPaginator integration (SQLite in-memory)", .serialized)
struct CursorPaginatorIntegrationTests {
    /// Runs a test against a fresh in-memory database, then reverts and shuts
    /// the application down.
    private func withApp<T>(
        _ body: (any Database) async throws -> T
    ) async throws -> T {
        // Create the application and its database pool.
        let app = try Application(.testing)
        let databases = Databases(threadPool: .singleton, on: .singletonMultiThreadedEventLoopGroup)
        databases.use(DatabaseConfigurationFactory.sqlite(.memory), as: .sqlite)
        app.addService(databases)

        // Run the test migration before the body.
        let migrations = Migrations()
        migrations.add(CreateTestUser())
        let migrator = Migrator(
            databases: databases,
            migrations: migrations,
            logger: Logger.current,
            on: .singletonMultiThreadedEventLoopGroup.any()
        )
        try await migrator.setupIfNeeded().get()
        try await migrator.prepareBatch().get()

        do {
            // Run the body, then revert and shut down.
            let database = try #require(
                databases.database(logger: Logger.current, on: .singletonMultiThreadedEventLoopGroup.any())
            )
            let result = try await body(database)
            try await migrator.revertAllBatches().get()
            await databases.shutdownAsync()
            try await app.shutdown()
            return result
        } catch {
            // Always revert and shut down, even when the body throws.
            try? await migrator.revertAllBatches().get()
            await databases.shutdownAsync()
            try? await app.shutdown()
            throw error
        }
    }

    private func makeRequest(url: String) -> Request {
        Request(method: .get, url: URI(string: url))
    }

    private func seed(_ db: any Database, _ count: Int) async throws {
        for i in 1...count {
            let u = TestUser(name: "user-\(i)")
            try await u.create(on: db)
        }
    }

    @Test
    func firstPageReturnsItemsAndHasMore() async throws {
        try await withApp { db in
            try await seed(db, 5)

            let request = makeRequest(url: "/users")
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
    }

    @Test
    func nextPageLoadsFollowingItems() async throws {
        try await withApp { db in
            try await seed(db, 5)

            // First page.
            let firstReq = makeRequest(url: "/users")
            let first: CursorPaginator<TestUser> = try await TestUser.query(on: db)
                .sort(\.$id)
                .cursorPaginate(perPage: 2, on: firstReq)
            let nextCursor = first.nextCursor()
            #expect(nextCursor != nil)
            let encoded = nextCursor!.encoded()

            // Second page using the next URL.
            let nextReq = makeRequest(url: "/users?cursor=\(encoded)")
            let second: CursorPaginator<TestUser> = try await TestUser.query(on: db)
                .sort(\.$id)
                .cursorPaginate(perPage: 2, on: nextReq)
            #expect(second.items.count == 2)
            #expect(second.cursor?.points == .next)
            #expect(second.items.first?.id != first.items.first?.id)
            #expect(second.hasMore == true)
        }
    }

    @Test
    func lastPageReportsNoMore() async throws {
        try await withApp { db in
            try await seed(db, 3)

            let request = makeRequest(url: "/users")
            let page: CursorPaginator<TestUser> = try await TestUser.query(on: db)
                .sort(\.$id)
                .cursorPaginate(perPage: 10, on: request)
            #expect(page.items.count == 3)
            #expect(page.hasMore == false)
            #expect(page.onLastPage == true)
            #expect(page.nextPageUrl() == nil)
        }
    }
}
