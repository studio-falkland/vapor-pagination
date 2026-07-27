import Testing
@testable import VaporPagination

struct CursorPaginatorTests {
    private struct User {
        let id: Int
        let name: String
    }

    private func makePaginator(
        items: [User],
        cursor: Cursor? = nil,
        hasMore: Bool,
        path: String = "https://api.example.com/users",
        cursorName: String = VaporPagination.defaultCursorName,
        query: [String: String] = [:],
        fragment: String? = nil
    ) -> CursorPaginator<User> {
        CursorPaginator(
            items: items,
            perPage: 3,
            cursor: cursor,
            hasMore: hasMore,
            path: path,
            cursorName: cursorName,
            query: query,
            fragment: fragment,
            orderColumn: "id",
            keyForElement: { String($0.id) }
        )
    }

    // MARK: - First page

    @Test
    func firstPageWithMore() {
        let p = makePaginator(
            items: [User(id: 1, name: "a"), User(id: 2, name: "b"), User(id: 3, name: "c")],
            hasMore: true
        )

        #expect(p.onFirstPage)
        #expect(!p.onLastPage)
        #expect(p.hasPages)
        #expect(p.hasMorePages)
        #expect(p.count == 3)
        #expect(p.items.count == 3)
        #expect(p.cursor == nil)

        #expect(p.nextCursor() == Cursor(points: .next, values: ["id": "3"]))
        #expect(p.previousCursor() == nil)

        let expectedNext = "https://api.example.com/users?cursor="
            + Cursor(points: .next, values: ["id": "3"]).encoded()
        #expect(p.nextPageUrl() == expectedNext)
        #expect(p.previousPageUrl() == nil)
    }

    // MARK: - Middle page

    @Test
    func middlePage() {
        let current = Cursor(points: .next, values: ["id": "3"])
        let p = makePaginator(
            items: [User(id: 4, name: "d"), User(id: 5, name: "e"), User(id: 6, name: "f")],
            cursor: current,
            hasMore: true
        )

        #expect(!p.onFirstPage)
        #expect(!p.onLastPage)
        #expect(p.hasPages)

        #expect(p.nextCursor() == Cursor(points: .next, values: ["id": "6"]))
        #expect(p.previousCursor() == Cursor(points: .previous, values: ["id": "4"]))

        #expect(p.nextPageUrl() != nil)
        #expect(p.previousPageUrl() != nil)
    }

    // MARK: - Last page

    @Test
    func lastPage() {
        let current = Cursor(points: .next, values: ["id": "6"])
        let p = makePaginator(
            items: [User(id: 7, name: "g"), User(id: 8, name: "h"), User(id: 9, name: "i")],
            cursor: current,
            hasMore: false
        )

        #expect(p.onLastPage)
        #expect(!p.hasMorePages)
        #expect(p.nextCursor() == nil)
        #expect(p.nextPageUrl() == nil)
        // Previous is still available since we arrived here via a cursor.
        #expect(p.previousCursor() == Cursor(points: .previous, values: ["id": "7"]))
        #expect(p.previousPageUrl() != nil)
    }

    // MARK: - hasPages edge

    @Test
    func hasPagesFalseWhenSinglePageAndNoMore() {
        let p = makePaginator(items: [User(id: 1, name: "a")], hasMore: false)
        #expect(!p.hasPages)
    }

    // MARK: - URL building

    @Test
    func urlWithAppendedQueryAndFragment() {
        let p = makePaginator(
            items: [User(id: 1, name: "a")],
            hasMore: true,
            query: ["sort": "name"],
            fragment: "users"
        )
        let cursor = Cursor(points: .next, values: ["id": "1"])
        #expect(
            p.url(cursor: cursor)
                == "https://api.example.com/users?sort=name&cursor=" + cursor.encoded() + "#users"
        )
    }

    @Test
    func urlWithNilCursorAndNoQueryIsBarePath() {
        let p = makePaginator(items: [User(id: 1, name: "a")], hasMore: false)
        #expect(p.url(cursor: nil) == "https://api.example.com/users")
    }

    @Test
    func urlWithNilCursorButQueryHasQueryPart() {
        let p = makePaginator(
            items: [User(id: 1, name: "a")],
            hasMore: false,
            query: ["sort": "name"]
        )
        #expect(p.url(cursor: nil) == "https://api.example.com/users?sort=name")
    }

    @Test
    func customCursorName() {
        let p = makePaginator(
            items: [User(id: 1, name: "a")],
            hasMore: true,
            cursorName: "page"
        )
        let cursor = Cursor(points: .next, values: ["id": "1"])
        #expect(p.url(cursor: cursor) == "https://api.example.com/users?page=" + cursor.encoded())
    }
}
