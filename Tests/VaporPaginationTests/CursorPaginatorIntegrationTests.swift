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

    private func seed(_ db: any Database, names: [String]) async throws -> [TestUser] {
        var users: [TestUser] = []
        for name in names {
            let u = TestUser(name: name)
            try await u.create(on: db)
            users.append(u)
        }
        return users
    }

    /// Walks every page forward, collecting the items in traversal order.
    private func collectAllPages(
        _ db: any Database,
        perPage: Int,
        orders: [CursorOrder],
        sort: (QueryBuilder<TestUser>) -> QueryBuilder<TestUser>
    ) async throws -> [TestUser] {
        var collected: [TestUser] = []
        var cursor: Cursor?

        // Bound the loop so a broken cursor cannot spin forever.
        for _ in 0..<20 {
            let url = cursor.map { "/users?cursor=" + $0.encoded() } ?? "/users"
            let request = makeRequest(url: url)
            let page: CursorPaginator<TestUser> = try await sort(TestUser.query(on: db))
                .cursorPaginate(
                    perPage: perPage,
                    on: request,
                    orders: orders,
                    valuesForElement: { user in
                        ["name": user.name, "id": user.id!.uuidString]
                    }
                )
            collected.append(contentsOf: page.items)

            guard let next = page.nextCursor() else { break }
            cursor = next
        }

        return collected
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

    // MARK: - Multi-column ordering

    @Test
    func multiColumnOrderingTraversesWithoutSkipsOrDuplicates() async throws {
        try await withApp { db in
            let seeded = try await seed(db, names: ["a", "a", "b", "b", "c", "c"])
            let expectedIDs = Set(seeded.compactMap(\.id))

            let collected = try await collectAllPages(
                db,
                perPage: 2,
                orders: [.ascending("name"), .ascending("id")]
            ) { query in
                query.sort(\.$name, .ascending).sort(\.$id, .ascending)
            }

            // Every row appears exactly once.
            #expect(collected.count == 6)
            #expect(Set(collected.compactMap(\.id)) == expectedIDs)

            // Names are non-decreasing across the traversal.
            let names = collected.map(\.name)
            #expect(names == names.sorted())
        }
    }

    @Test
    func multiColumnMixedDirectionsTraverseWithoutSkipsOrDuplicates() async throws {
        try await withApp { db in
            let seeded = try await seed(db, names: ["a", "a", "b", "b", "c", "c"])
            let expectedIDs = Set(seeded.compactMap(\.id))

            let collected = try await collectAllPages(
                db,
                perPage: 2,
                orders: [.ascending("name"), .descending("id")]
            ) { query in
                query.sort(\.$name, .ascending).sort(\.$id, .descending)
            }

            #expect(collected.count == 6)
            #expect(Set(collected.compactMap(\.id)) == expectedIDs)

            // Names are non-decreasing even though the tie-breaker is descending.
            let names = collected.map(\.name)
            #expect(names == names.sorted())
        }
    }

    @Test
    func orderDirectionIsUsedWhenNoSortIsDeclared() async throws {
        try await withApp { db in
            let seeded = try await seed(db, names: ["a", "a", "b", "b", "c", "c"])
            let expectedIDs = Set(seeded.compactMap(\.id))

            let collected = try await collectAllPages(
                db,
                perPage: 2,
                orders: [.descending("name"), .ascending("id")]
            ) { query in
                // No `.sort` calls: the library applies the order directions.
                query
            }

            #expect(collected.count == 6)
            #expect(Set(collected.compactMap(\.id)) == expectedIDs)

            // Names are non-increasing because the primary order is descending.
            let names = collected.map(\.name)
            #expect(names == names.sorted(by: >))
        }
    }
}
