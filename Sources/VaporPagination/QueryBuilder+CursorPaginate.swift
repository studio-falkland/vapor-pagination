import Fluent
import Foundation
import Vapor

extension QueryBuilder {
    /// Returns a cursor-paginated page of models.
    ///
    /// Performs the equivalent of `WHERE col <op> value` + `LIMIT
    /// perPage + 1`, with the extra row used to detect `hasMore`.
    /// Backward traversal reverses the sort + result in memory.
    ///
    /// Single-column ordering for v1 — `orderColumn` defaults to the
    /// model's `@ID` (`$id`). The caller must declare the same sort
    /// (`sort`) before invoking this, e.g. `.sort(\.$id)`.
    ///
    /// - Parameter perPage: Number of items per page.
    /// - Parameter request: The current HTTP request (used to read the cursor
    ///   from the query string and build page URLs).
    /// - Parameter orderColumn: The database column to order and cursor by.
    ///   Defaults to `"id"` (the model's `@ID`).
    /// - Parameter cursorName: Query-string parameter name carrying the cursor.
    ///   Defaults to `"cursor"`.
    /// - Parameter keyForElement: Extracts the stringified cursor-anchor value
    ///   from a model. For the default `"id"` order column the library handles
    ///   this automatically. For custom columns you must provide a closure that
    ///   returns a string representation of the column's value.
    ///
    ///   For example, ordering by `"createdAt"`:
    ///   ```swift
    ///   try await Article.query(on: req.db)
    ///       .sort(\.$createdAt, .ascending)
    ///       .cursorPaginate(perPage: 20, on: req, orderColumn: "createdAt") { article in
    ///           String(article.createdAt.timeIntervalSince1970)
    ///       }
    ///   ```
    public func cursorPaginate(
        perPage: Int,
        on request: Request,
        orderColumn: String? = nil,
        cursorName: String = VaporPagination.defaultCursorName,
        keyForElement: @escaping (Model) -> String
    ) async throws -> CursorPaginator<Model> {
        try await self._cursorPaginate(
            perPage: perPage,
            on: request,
            orderColumn: orderColumn,
            cursorName: cursorName,
            keyForElement: keyForElement
        )
    }

    /// Overload with a default `keyForElement` that reads `model.id`.
    /// This overload exists because `Self.keyValue(of:)` cannot be referenced
    /// from a default argument expression on an `extension QueryBuilder` method.
    public func cursorPaginate(
        perPage: Int,
        on request: Request,
        orderColumn: String? = nil,
        cursorName: String = VaporPagination.defaultCursorName
    ) async throws -> CursorPaginator<Model> {
        try await self._cursorPaginate(
            perPage: perPage,
            on: request,
            orderColumn: orderColumn,
            cursorName: cursorName,
            keyForElement: { Self.keyValue(of: $0) }
        )
    }

    // MARK: - Core implementation

    private func _cursorPaginate(
        perPage: Int,
        on request: Request,
        orderColumn: String?,
        cursorName: String,
        keyForElement: @escaping (Model) -> String
    ) async throws -> CursorPaginator<Model> {
        let cursor = Cursor(from: request.query[String.self, at: cursorName])
        let resolvedOrderColumn = orderColumn ?? Self.idKeyString(for: Model.self)
        let anchor = cursor?.values[resolvedOrderColumn]

        // If the caller declared a sort on the order column, honor its
        // direction; otherwise default to ascending.
        let isDescending = Self.detectDescending(
            query: self.query,
            declaredColumn: resolvedOrderColumn
        )

        // For backward traversal, flip both the predicate and the sort
        // direction.
        let reverse = cursor?.points == .previous
        let op: DatabaseQuery.Filter.Method = reverse
            ? (isDescending ? .greaterThan : .lessThan)
            : (isDescending ? .lessThan : .greaterThan)

        let sortDirection: DatabaseQuery.Sort.Direction = reverse
            ? (isDescending ? .ascending : .descending)
            : (isDescending ? .descending : .ascending)

        // Build the limited query directly against the DatabaseQuery struct
        // so we control the exact FieldKey used.
        var working = self.query

        // Only add the WHERE filter when there is a cursor anchor.
        // On the first page (no cursor) there is no anchor to filter by.
        if let anchor, let filterValue = Self.parseLiteral(anchor) {
            working.filters.append(.value(
                .extendedPath([.string(resolvedOrderColumn)], schema: Model.schemaOrAlias, space: Model.spaceIfNotAliased),
                op,
                filterValue
            ))
        }

        // Remove any existing sort on the order column so we can replace it
        // with one that uses the correct direction (including reversal for
        // backward traversal). Matches both `.id` and `.string("name")`
        // FieldKey forms.
        working.sorts = working.sorts.filter { sort in
            if case .sort(let field, _) = sort, case .path(let keys, _) = field {
                guard keys.count == 1 else { return true }
                return !Self.fieldKeyMatchesColumn(keys[0], resolvedOrderColumn)
            }
            return true
        }
        working.sorts.append(
            .sort(
                .extendedPath([.string(resolvedOrderColumn)], schema: Model.schemaOrAlias, space: Model.spaceIfNotAliased),
                sortDirection
            )
        )
        working.limits = [.count(perPage + 1)]
        working.offsets = [.count(0)]
        self.query = working

        let fetched: [Model] = try await self.all()

        var items = fetched
        let hasMore = items.count > perPage
        if hasMore { items.removeLast() }
        if reverse { items.reverse() }

        return CursorPaginator(
            items: items,
            perPage: perPage,
            cursor: cursor,
            hasMore: hasMore,
            path: request.paginationPath,
            cursorName: cursorName,
            query: request.appendedQuery(excluding: cursorName),
            orderColumn: resolvedOrderColumn,
            keyForElement: keyForElement
        )
    }

    // MARK: - Helpers

    private static func idKeyString(for _: Model.Type) -> String {
        "id"
    }

    /// Returns `true` when the query already contains a `DESC` sort on
    /// `declaredColumn`. Matches both `.id` and `.string("name")` FieldKey
    /// forms so that `.sort(\.$id)` (which produces `.path([.id])`) is
    /// detected correctly.
    private static func detectDescending(
        query: DatabaseQuery,
        declaredColumn: String
    ) -> Bool {
        for sort in query.sorts {
            if case .sort(let field, let direction) = sort {
                if case .path(let keys, _) = field, keys.count == 1 {
                    if Self.fieldKeyMatchesColumn(keys[0], declaredColumn) {
                        if case .descending = direction { return true }
                        return false
                    }
                }
            }
        }
        return false
    }

    /// Returns `true` when `key` refers to the same database column as `column`.
    ///
    /// Fluent's `@ID` produces `.path([.id])` while raw column references
    /// produce `.path([.string("id")])`. This helper treats both as matching
    /// `"id"`.
    private static func fieldKeyMatchesColumn(_ key: FieldKey, _ column: String) -> Bool {
        switch key {
        case .id:
            return column == "id"
        case .string(let s):
            return s == column
        default:
            return false
        }
    }

    /// Converts a cursor-anchor string back into a `DatabaseQuery.Value`
    /// with the correct runtime type so the SQL driver binds it properly.
    ///
    /// Recognises, in order:
    /// - `Int` (including `Int64`)
    /// - `UUID`
    /// - ISO 8601 date (e.g. `2024-01-15T10:30:00Z`)
    /// - Unix timestamp as `Double` (e.g. `1705312200.0`)
    /// - Falls back to plain text
    private static func parseLiteral(_ value: String?) -> DatabaseQuery.Value? {
        guard let value, !value.isEmpty else { return nil }
        if let i = Int(value) { return .bind(i) }
        if let i = Int64(value) { return .bind(i) }
        if let u = UUID(uuidString: value) { return .bind(u) }
        if let d = ISO8601DateFormatter().date(from: value) { return .bind(d) }
        if let t = Double(value) { return .bind(Date(timeIntervalSince1970: t)) }
        return .bind(value)
    }

    /// Default anchor-value extractor — reads `model.id` and returns a
    /// string representation. Used automatically when `orderColumn` is `"id"`.
    private static func keyValue(of model: Model) -> String {
        if let id = model.id as? String { return id }
        if let id = model.id as? Int { return String(id) }
        if let id = model.id as? Int64 { return String(id) }
        if let id = model.id as? UUID { return id.uuidString }
        return String(describing: model.id)
    }
}