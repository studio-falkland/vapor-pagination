import Testing
@testable import VaporPagination

struct CursorPaginatedResponseTests {
    private struct User: Codable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    private struct UserDTO: Codable, Sendable, Equatable {
        let displayName: String
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

    // MARK: - makeResponse()

    @Test
    func makeResponseFirstPageWithMore() {
        let paginator = makePaginator(
            items: [User(id: 1, name: "a"), User(id: 2, name: "b"), User(id: 3, name: "c")],
            hasMore: true
        )
        let response = paginator.makeResponse()

        #expect(response.data == paginator.items)
        #expect(response.links.next == paginator.nextPageUrl())
        #expect(response.links.previous == paginator.previousPageUrl())
        #expect(response.meta.perPage == paginator.perPage)
        #expect(response.meta.hasMorePages == paginator.hasMore)
        #expect(response.meta.onFirstPage == paginator.onFirstPage)
        #expect(response.meta.onLastPage == paginator.onLastPage)
        #expect(response.meta.cursor == nil)
        #expect(response.meta.cursorName == paginator.cursorName)
        #expect(response.meta.path == paginator.path)
    }

    @Test
    func makeResponseMiddlePage() {
        let current = Cursor(points: .next, values: ["id": "3"])
        let paginator = makePaginator(
            items: [User(id: 4, name: "d"), User(id: 5, name: "e"), User(id: 6, name: "f")],
            cursor: current,
            hasMore: true
        )
        let response = paginator.makeResponse()

        #expect(response.data == paginator.items)
        #expect(response.links.next == paginator.nextPageUrl())
        #expect(response.links.previous == paginator.previousPageUrl())
        #expect(response.meta.hasMorePages == true)
        #expect(response.meta.onFirstPage == false)
        #expect(response.meta.onLastPage == false)
        #expect(response.meta.cursor == current.encoded())
        #expect(response.meta.cursorName == paginator.cursorName)
        #expect(response.meta.path == paginator.path)
    }

    @Test
    func makeResponseLastPage() {
        let current = Cursor(points: .next, values: ["id": "6"])
        let paginator = makePaginator(
            items: [User(id: 7, name: "g"), User(id: 8, name: "h"), User(id: 9, name: "i")],
            cursor: current,
            hasMore: false
        )
        let response = paginator.makeResponse()

        #expect(response.data == paginator.items)
        #expect(response.links.next == nil)
        #expect(response.links.previous != nil)
        #expect(response.meta.hasMorePages == false)
        #expect(response.meta.onFirstPage == false)
        #expect(response.meta.onLastPage == true)
        #expect(response.meta.cursor == current.encoded())
    }

    @Test
    func makeResponseEmptyItems() {
        let paginator = makePaginator(
            items: [],
            hasMore: false
        )
        let response = paginator.makeResponse()

        #expect(response.data.isEmpty)
        #expect(response.links.next == nil)
        #expect(response.links.previous == nil)
        #expect(response.meta.hasMorePages == false)
        #expect(response.meta.onFirstPage == true)
        #expect(response.meta.onLastPage == true)
        #expect(response.meta.cursor == nil)
    }

    // MARK: - responding(with:)

    @Test
    func respondingTransformsItems() {
        let paginator = makePaginator(
            items: [User(id: 1, name: "Alice"), User(id: 2, name: "Bob"), User(id: 3, name: "Charlie")],
            hasMore: true
        )

        let response: CursorPaginatedResponse<UserDTO> = paginator.responding { user in
            UserDTO(displayName: user.name.uppercased())
        }

        let expected = [
            UserDTO(displayName: "ALICE"),
            UserDTO(displayName: "BOB"),
            UserDTO(displayName: "CHARLIE"),
        ]
        #expect(response.data == expected)
    }

    @Test
    func respondingPreservesLinksAndMeta() {
        let paginator = makePaginator(
            items: [User(id: 1, name: "a"), User(id: 2, name: "b"), User(id: 3, name: "c")],
            hasMore: true
        )

        let response: CursorPaginatedResponse<UserDTO> = paginator.responding { user in
            UserDTO(displayName: user.name)
        }

        // Links match the original paginator.
        #expect(response.links.next == paginator.nextPageUrl())
        #expect(response.links.previous == paginator.previousPageUrl())

        // Meta matches the original paginator.
        #expect(response.meta.perPage == paginator.perPage)
        #expect(response.meta.hasMorePages == paginator.hasMore)
        #expect(response.meta.onFirstPage == paginator.onFirstPage)
        #expect(response.meta.onLastPage == paginator.onLastPage)
        #expect(response.meta.cursor == nil)
        #expect(response.meta.cursorName == paginator.cursorName)
        #expect(response.meta.path == paginator.path)
    }

    @Test
    func respondingWithCursorRetainsCursorInMeta() {
        let current = Cursor(points: .next, values: ["id": "3"])
        let paginator = makePaginator(
            items: [User(id: 4, name: "d"), User(id: 5, name: "e")],
            cursor: current,
            hasMore: false
        )

        let response: CursorPaginatedResponse<UserDTO> = paginator.responding { user in
            UserDTO(displayName: user.name)
        }

        #expect(response.meta.cursor == current.encoded())
        #expect(response.meta.onFirstPage == false)
        #expect(response.meta.onLastPage == true)
        #expect(response.meta.hasMorePages == false)
    }

    @Test
    func respondingOnLastPageHasNilNext() {
        let current = Cursor(points: .next, values: ["id": "6"])
        let paginator = makePaginator(
            items: [User(id: 7, name: "g")],
            cursor: current,
            hasMore: false
        )

        let response: CursorPaginatedResponse<UserDTO> = paginator.responding { user in
            UserDTO(displayName: user.name)
        }

        #expect(response.links.next == nil)
        #expect(response.data.count == 1)
    }

    @Test
    func respondingOnFirstPageHasNilPrevious() {
        let paginator = makePaginator(
            items: [User(id: 1, name: "a"), User(id: 2, name: "b")],
            hasMore: true
        )

        let response: CursorPaginatedResponse<UserDTO> = paginator.responding { user in
            UserDTO(displayName: user.name)
        }

        #expect(response.links.previous == nil)
        #expect(response.links.next != nil)
    }
}