import FluentKit
import Foundation
import Vapor

extension QueryBuilder {
    /// Returns a cursor-paginated page of models ordered by multiple columns.
    ///
    /// Builds a lexicographic keyset predicate from the cursor values:
    ///
    /// ```sql
    /// (c0 > v0)
    /// OR (c0 = v0 AND c1 > v1)
    /// OR (c0 = v0 AND c1 = v1 AND c2 > v2)
    /// ```
    ///
    /// Each comparison follows its column's direction, and the whole predicate
    /// and sort order are reversed for backward traversal. The query fetches
    /// `perPage + 1` rows so the extra row can signal `hasMore`.
    ///
    /// The `orders` array defines the column precedence. If the query already
    /// declares a sort on one of those columns, its direction takes precedence
    /// over the direction in the corresponding `CursorOrder`; otherwise the
    /// `CursorOrder` direction is used.
    ///
    /// - Parameter perPage: Number of items per page.
    /// - Parameter request: The current HTTP request (used to read the cursor
    ///   from the query string and build page URLs).
    /// - Parameter orders: The ordering terms, in precedence order.
    /// - Parameter cursorName: Query-string parameter name carrying the cursor.
    ///   Defaults to `"cursor"`.
    /// - Parameter baseURL: An optional origin override for generated page URLs.
    /// - Parameter valuesForElement: Extracts the stringified anchor values for
    ///   a model, keyed by column name. Every column in `orders` must be
    ///   present, and each value must round-trip through the library's literal
    ///   parser (`Int`, `UUID`, ISO 8601 date, Unix timestamp, or text).
    ///
    /// ```swift
    /// try await User.query(on: database)
    ///     .sort(\.$lastName, .ascending)
    ///     .sort(\.$firstName, .ascending)
    ///     .sort(\.$id, .ascending)
    ///     .cursorPaginate(
    ///         perPage: 20,
    ///         on: req,
    ///         orders: [.ascending("lastName"), .ascending("firstName"), .ascending("id")]
    ///     ) { user in
    ///         [
    ///             "lastName": user.lastName,
    ///             "firstName": user.firstName,
    ///             "id": user.id!.uuidString,
    ///         ]
    ///     }
    /// ```
    public func cursorPaginate(
        perPage: Int,
        on request: Request,
        orders: [CursorOrder],
        cursorName: String = VaporPagination.defaultCursorName,
        baseURL: URL? = nil,
        valuesForElement: @escaping (Model) -> [String: String]
    ) async throws -> CursorPaginator<Model> {
        try await self._cursorPaginate(
            perPage: perPage,
            on: request,
            orders: orders,
            cursorName: cursorName,
            baseURL: baseURL,
            valuesForElement: valuesForElement
        )
    }

    /// Returns a cursor-paginated page of models ordered by a single column.
    ///
    /// Performs the equivalent of `WHERE col <op> value` + `LIMIT
    /// perPage + 1`, with the extra row used to detect `hasMore`.
    /// Backward traversal reverses the sort + result in memory.
    ///
    /// `orderColumn` defaults to the model's `@ID` (`$id`). The caller must
    /// declare the same sort (`sort`) before invoking this, e.g. `.sort(\.$id)`.
    ///
    /// - Parameter perPage: Number of items per page.
    /// - Parameter request: The current HTTP request (used to read the cursor
    ///   from the query string and build page URLs).
    /// - Parameter orderColumn: The database column to order and cursor by.
    ///   Defaults to `"id"` (the model's `@ID`).
    /// - Parameter cursorName: Query-string parameter name carrying the cursor.
    ///   Defaults to `"cursor"`.
    /// - Parameter baseURL: An optional origin override for generated page URLs.
    /// - Parameter keyForElement: Extracts the stringified cursor-anchor value
    ///   from a model. For the default `"id"` order column the library handles
    ///   this automatically. For custom columns you must provide a closure that
    ///   returns a string representation of the column's value.
    ///
    ///   For example, ordering by `"createdAt"`:
    ///   ```swift
    ///   try await Article.query(on: database)
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
        baseURL: URL? = nil,
        keyForElement: @escaping (Model) -> String
    ) async throws -> CursorPaginator<Model> {
        let column = orderColumn ?? Self.idKeyString(for: Model.self)
        return try await self._cursorPaginate(
            perPage: perPage,
            on: request,
            orders: [CursorOrder(column: column)],
            cursorName: cursorName,
            baseURL: baseURL,
            valuesForElement: { [column: keyForElement($0)] }
        )
    }

    /// Overload with a default `keyForElement` that reads `model.id`.
    /// This overload exists because `Self.keyValue(of:)` cannot be referenced
    /// from a default argument expression on an `extension QueryBuilder` method.
    public func cursorPaginate(
        perPage: Int,
        on request: Request,
        orderColumn: String? = nil,
        cursorName: String = VaporPagination.defaultCursorName,
        baseURL: URL? = nil
    ) async throws -> CursorPaginator<Model> {
        let column = orderColumn ?? Self.idKeyString(for: Model.self)
        return try await self._cursorPaginate(
            perPage: perPage,
            on: request,
            orders: [CursorOrder(column: column)],
            cursorName: cursorName,
            baseURL: baseURL,
            valuesForElement: { [column: Self.keyValue(of: $0)] }
        )
    }

    // MARK: - Core implementation

    private func _cursorPaginate(
        perPage: Int,
        on request: Request,
        orders: [CursorOrder],
        cursorName: String,
        baseURL: URL?,
        valuesForElement: @escaping (Model) -> [String: String]
    ) async throws -> CursorPaginator<Model> {
        let cursor = Cursor(from: request.query[String.self, at: cursorName])

        // Fall back to the model's `@ID` when no ordering is supplied.
        let requestedOrders = orders.isEmpty
            ? [CursorOrder(column: Self.idKeyString(for: Model.self))]
            : orders

        // A sort declared on the query overrides the order's direction.
        let resolvedOrders = requestedOrders.map { order in
            CursorOrder(
                column: order.column,
                direction: Self.detectDirection(query: self.query, column: order.column) ?? order.direction
            )
        }

        // Backward traversal flips both the predicate and the sort directions.
        let reverse = cursor?.points == .previous

        var working = self.query

        // Add the keyset predicate only when there is a cursor anchor.
        if let cursor, let filter = Self.keysetFilter(orders: resolvedOrders, cursor: cursor, reverse: reverse) {
            working.filters.append(filter)
        }

        // Replace any declared sorts on the order columns with the resolved
        // directions, preserving the precedence of `resolvedOrders`.
        let orderColumns = resolvedOrders.map(\.column)
        working.sorts = working.sorts.filter { sort in
            guard case .sort(let field, _) = sort, case .path(let keys, _) = field, keys.count == 1 else {
                return true
            }
            return !orderColumns.contains { Self.fieldKeyMatchesColumn(keys[0], $0) }
        }
        for order in resolvedOrders {
            working.sorts.append(.sort(
                Self.field(for: order.column),
                Self.sortDirection(for: order.direction, reverse: reverse)
            ))
        }

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
            path: request.paginationPath(baseURL: baseURL),
            cursorName: cursorName,
            query: request.appendedQuery(excluding: cursorName),
            orders: resolvedOrders,
            valuesForElement: valuesForElement
        )
    }

    // MARK: - Helpers

    private static func idKeyString(for _: Model.Type) -> String {
        "id"
    }

    /// Builds the lexicographic keyset predicate for the given cursor.
    ///
    /// Only the longest prefix of `orders` for which the cursor carries a
    /// value is used, so a cursor anchored on fewer columns still produces a
    /// valid predicate.
    private static func keysetFilter(
        orders: [CursorOrder],
        cursor: Cursor,
        reverse: Bool
    ) -> DatabaseQuery.Filter? {
        // Collect the cursor values for the leading run of ordered columns.
        var terms: [(order: CursorOrder, value: DatabaseQuery.Value)] = []
        for order in orders {
            guard let raw = cursor[order.column], let value = Self.parseLiteral(raw) else { break }
            terms.append((order, value))
        }
        guard !terms.isEmpty else { return nil }

        // Build `(c0 <op> v0) OR (c0 = v0 AND c1 <op> v1) OR ...`.
        var disjuncts: [DatabaseQuery.Filter] = []
        for (index, term) in terms.enumerated() {
            var conjuncts: [DatabaseQuery.Filter] = []

            // Equality on every preceding column.
            for previous in terms[..<index] {
                conjuncts.append(.value(
                    Self.field(for: previous.order.column),
                    .equal,
                    previous.value
                ))
            }

            // The strict comparison on this column, flipped for backward traversal.
            let greater = reverse
                ? term.order.direction == .descending
                : term.order.direction == .ascending
            conjuncts.append(.value(
                Self.field(for: term.order.column),
                greater ? .greaterThan : .lessThan,
                term.value
            ))

            disjuncts.append(conjuncts.count == 1 ? conjuncts[0] : .group(conjuncts, .and))
        }

        return disjuncts.count == 1 ? disjuncts[0] : .group(disjuncts, .or)
    }

    /// Returns the direction of a sort already declared on `column`, or `nil`
    /// when the query has no sort on that column.
    ///
    /// Matches both `.id` and `.string("name")` FieldKey forms so that
    /// `.sort(\.$id)` (which produces `.path([.id])`) is detected correctly.
    private static func detectDirection(
        query: DatabaseQuery,
        column: String
    ) -> CursorOrder.Direction? {
        for sort in query.sorts {
            guard case .sort(let field, let direction) = sort,
                  case .path(let keys, _) = field,
                  keys.count == 1,
                  Self.fieldKeyMatchesColumn(keys[0], column)
            else { continue }

            switch direction {
            case .ascending: return .ascending
            case .descending: return .descending
            case .custom: return nil
            }
        }
        return nil
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

    /// Builds a fully-qualified field reference for a raw column name.
    private static func field(for column: String) -> DatabaseQuery.Field {
        .extendedPath(
            [.string(column)],
            schema: Model.schemaOrAlias,
            space: Model.spaceIfNotAliased
        )
    }

    /// Maps a cursor order direction to a Fluent sort direction, reversing it
    /// for backward traversal.
    private static func sortDirection(
        for direction: CursorOrder.Direction,
        reverse: Bool
    ) -> DatabaseQuery.Sort.Direction {
        switch (direction, reverse) {
        case (.ascending, false), (.descending, true): return .ascending
        case (.descending, false), (.ascending, true): return .descending
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
