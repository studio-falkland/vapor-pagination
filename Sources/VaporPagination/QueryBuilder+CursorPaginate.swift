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
    public func cursorPaginate(
        perPage: Int,
        on request: Request,
        orderColumn: String? = nil,
        cursorName: String = VaporPagination.defaultCursorName
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

        let filterValue = Self.parseLiteral(anchor) ?? .bind(anchor ?? "")

        // Build the limited query directly against the DatabaseQuery struct
        // so we control the exact FieldKey used.
        var working = self.query
        working.filters.append(.value(
            .extendedPath([.string(resolvedOrderColumn)], schema: Model.schemaOrAlias, space: Model.spaceIfNotAliased),
            op,
            filterValue
        ))
        working.sorts = working.sorts.filter { sort in
            if case .sort(let field, _) = sort, case .path(let keys, _) = field {
                return !(keys.count == 1 && keys[0] == .string(resolvedOrderColumn))
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
            keyForElement: { Self.keyValue(of: $0) }
        )
    }

    // MARK: - Helpers

    private static func idKeyString(for _: Model.Type) -> String {
        "id"
    }

    private static func detectDescending(
        query: DatabaseQuery,
        declaredColumn: String
    ) -> Bool {
        for sort in query.sorts {
            if case .sort(let field, let direction) = sort {
                if case .path(let keys, _) = field, keys.count == 1, keys[0] == .string(declaredColumn) {
                    if case .descending = direction { return true }
                    return false
                }
            }
        }
        return false
    }

    private static func parseLiteral(_ value: String?) -> DatabaseQuery.Value? {
        guard let value, !value.isEmpty else { return nil }
        if let i = Int(value) { return .bind(i) }
        if let u = UUID(uuidString: value) { return .bind(u) }
        return .bind(value)
    }

    private static func keyValue(of model: Model) -> String {
        if let id = model.id as? String { return id }
        if let id = model.id as? Int { return String(id) }
        if let id = model.id as? UUID { return id.uuidString }
        return String(describing: model.id)
    }
}