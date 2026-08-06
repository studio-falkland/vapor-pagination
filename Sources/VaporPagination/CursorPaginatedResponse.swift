import Vapor

/// A `ResponseEncodable` wrapper around a `CursorPaginator` that renders
/// the JSON envelope:
///
/// ```json
/// {
///   "data": [ ... ],
///   "links": { "next": "...", "previous": null },
///   "meta": { "perPage": 15, "hasMorePages": true, "cursor": "...", ... }
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
        /// The cursor for the next page, encoded as base64url.
        /// `nil` on the last page.
        public let cursor: String?
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
                cursor: self.nextCursor()?.encoded()
            )
        )
    }

    /// Maps items through a transform and returns a `CursorPaginatedResponse`.
    ///
    /// This is the recommended way to return paginated results when your route
    /// uses a DTO (or any other response type) instead of the raw model. Cursor
    /// metadata — links, `hasMore`, cursor strings — is derived from the
    /// model-level paginator and is unaffected by the transform.
    ///
    /// - Parameter transform: Closure that converts each `Element` (typically a
    ///   Fluent model) into the response type `T` (typically a DTO).
    /// - Returns: A `CursorPaginatedResponse<T>` ready to return from a route.
    public func responding<T: Codable & Sendable>(
        with transform: (Element) -> T
    ) -> CursorPaginatedResponse<T> {
        CursorPaginatedResponse<T>(
            data: items.map(transform),
            links: .init(next: nextPageUrl(), previous: previousPageUrl()),
            meta: .init(perPage: perPage, hasMorePages: hasMore, onFirstPage: onFirstPage, onLastPage: onLastPage, cursor: nextCursor()?.encoded())
        )
    }

}
