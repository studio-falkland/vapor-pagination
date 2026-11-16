import Foundation

/// A page of results plus the cursor-pagination metadata needed to
/// navigate forward and backward.
///
/// A paginator is a pure value type with no database coupling. Callers
/// construct it from in-memory items, the ordering terms, and a closure that
/// extracts the cursor-anchor values for each item. `QueryBuilder.cursorPaginate`
/// builds instances from Fluent queries.
public struct CursorPaginator<Element> {
    /// The items on the current page.
    public let items: [Element]

    /// Items per page.
    public let perPage: Int

    /// The cursor this page was produced from. `nil` == first page.
    public let cursor: Cursor?

    /// Whether more items exist beyond this page.
    public let hasMore: Bool

    /// Base path used when building page URLs.
    public let path: String

    /// Query-string parameter name carrying the cursor.
    public var cursorName: String

    /// Extra query-string parameters appended to every generated URL.
    public var query: [String: String]

    /// Optional URL fragment appended to generated URLs.
    public var fragment: String?

    /// The ordering terms cursors are anchored to, in precedence order.
    public let orders: [CursorOrder]

    /// Extracts the typed anchor values for a given element, keyed by column
    /// name.
    public let valuesForElement: (Element) -> [String: CursorValue]

    public init(
        items: [Element],
        perPage: Int,
        cursor: Cursor?,
        hasMore: Bool,
        path: String,
        cursorName: String = VaporPagination.defaultCursorName,
        query: [String: String] = [:],
        fragment: String? = nil,
        orders: [CursorOrder],
        valuesForElement: @escaping (Element) -> [String: CursorValue]
    ) {
        self.items = items
        self.perPage = perPage
        self.cursor = cursor
        self.hasMore = hasMore
        self.path = path
        self.cursorName = cursorName
        self.query = query
        self.fragment = fragment
        self.orders = orders
        self.valuesForElement = valuesForElement
    }

    /// Convenience initializer for single-column ordering with a typed value.
    public init(
        items: [Element],
        perPage: Int,
        cursor: Cursor?,
        hasMore: Bool,
        path: String,
        cursorName: String = VaporPagination.defaultCursorName,
        query: [String: String] = [:],
        fragment: String? = nil,
        orderColumn: String,
        valueForElement: @escaping (Element) -> CursorValue
    ) {
        self.init(
            items: items,
            perPage: perPage,
            cursor: cursor,
            hasMore: hasMore,
            path: path,
            cursorName: cursorName,
            query: query,
            fragment: fragment,
            orders: [CursorOrder(column: orderColumn)],
            valuesForElement: { [orderColumn: valueForElement($0)] }
        )
    }
}

public extension CursorPaginator {
    /// Number of items on the current page.
    var count: Int { items.count }

    /// Whether there are enough items to split into multiple pages.
    var hasPages: Bool { !onFirstPage || hasMore }

    /// Whether more items exist beyond this page.
    var hasMorePages: Bool { hasMore }

    /// Whether this is the first page.
    var onFirstPage: Bool { cursor == nil }

    /// Whether this is the last page.
    var onLastPage: Bool { !hasMore }

    /// The first ordering column. Retained for single-column callers.
    var orderColumn: String { orders.first?.column ?? "id" }

    // MARK: - Cursor derivation

    /// Cursor for the next page, anchored at the last item of this page.
    /// Returns nil when there are no more pages or no items.
    func nextCursor() -> Cursor? {
        guard hasMore, let last = items.last else { return nil }
        return Cursor(points: .next, values: valuesForElement(last))
    }

    /// Cursor for the previous page, anchored at the first item of this page.
    /// Returns nil on the first page or when there are no items.
    func previousCursor() -> Cursor? {
        guard cursor != nil, let first = items.first else { return nil }
        return Cursor(points: .previous, values: valuesForElement(first))
    }

    // MARK: - URLs

    /// URL for the next page.
    func nextPageUrl() -> String? {
        guard let c = nextCursor() else { return nil }
        return url(cursor: c)
    }

    /// URL for the previous page.
    func previousPageUrl() -> String? {
        guard let c = previousCursor() else { return nil }
        return url(cursor: c)
    }

    /// Build a URL for a given cursor instance.
    func url(cursor c: Cursor?) -> String {
        guard var components = URLComponents(string: path) else { return path }

        var items = components.queryItems ?? []
        for (key, value) in query {
            items.append(URLQueryItem(name: key, value: value))
        }
        if let c {
            items.append(URLQueryItem(name: cursorName, value: c.encoded()))
        }
        if !items.isEmpty {
            components.queryItems = items
        }
        components.fragment = fragment
        return components.string ?? path
    }
}
