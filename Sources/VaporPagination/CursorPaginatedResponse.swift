import Vapor

/// A `ResponseEncodable` wrapper around a `CursorPaginator` that renders
/// the JSON envelope:
///
/// ```json
/// {
///   "data": [ ... ],
///   "links": { "next": "...", "previous": null },
///   "meta": { "perPage": 15, "hasMorePages": true, ... }
/// }
/// ```
public struct CursorPaginatedResponse<Element: Codable & Sendable>: Content {
    /// The items on the current page.
    public let data: [Element]

    /// Navigation links for the next and previous pages.
    public let links: Links

    /// Pagination metadata.
    public let meta: Meta

    public struct Links: Codable, Sendable {
        /// URL for the next page, or nil if on the last page.
        public let next: String?
        /// URL for the previous page, or nil if on the first page.
        public let previous: String?
    }

    public struct Meta: Codable, Sendable {
        /// Items per page.
        public let perPage: Int
        /// Whether more items exist beyond this page.
        public let hasMorePages: Bool
        /// Whether this is the first page.
        public let onFirstPage: Bool
        /// Whether this is the last page.
        public let onLastPage: Bool
        /// The current cursor, encoded as base64url.
        public let cursor: String?
        /// The query-string parameter name carrying the cursor.
        public let cursorName: String
        /// The base path used for pagination URLs.
        public let path: String
    }
}

extension CursorPaginator {
    /// Converts the paginator into a `CursorPaginatedResponse` suitable
    /// for returning from a Vapor route. Requires `Element: Codable`
    /// so the items can be serialized as JSON.
    public func makeResponse() -> CursorPaginatedResponse<Element> where Element: Codable & Sendable {
        CursorPaginatedResponse(
            data: self.items,
            links: .init(
                next: self.nextPageUrl(),
                previous: self.previousPageUrl()
            ),
            meta: .init(
                perPage: self.perPage,
                hasMorePages: self.hasMore,
                onFirstPage: self.onFirstPage,
                onLastPage: self.onLastPage,
                cursor: self.cursor?.encoded(),
                cursorName: self.cursorName,
                path: self.path
            )
        )
    }
}