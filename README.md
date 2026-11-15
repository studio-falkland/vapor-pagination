<p align="center">
<img src="./Documentation/logo.svg" />
</p>

<p></p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.4+-F05138?logo=swift&logoColor=white" alt="Swift 6.4+"></a>
  <a href="https://github.com/vapor/vapor"><img src="https://img.shields.io/badge/Vapor-5-6DBEEB?logo=vapor&logoColor=white" alt="Vapor 5"></a>
  <a href="https://swift.org/package-manager"><img src="https://img.shields.io/badge/SPM-compatible-4BC51D?logo=swift&logoColor=white" alt="SPM Compatible"></a>
  <a href="https://github.com/studio-falkland/vapor-pagination/releases"><img src="https://img.shields.io/github/v/release/studio-falkland/vapor-pagination?color=blue" alt="Latest Release"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/github/license/studio-falkland/vapor-pagination" alt="License"></a>
</p>

## Introduction
`vapor-pagination` is a cursor-based pagination library for Swift Vapor and
Fluent. Instead of paginating with `OFFSET`, it pages with a `WHERE` clause
on the ordered column(s), which is efficient for large datasets (when the
order column is indexed) and stable under concurrent writes — no skipped or
duplicated rows when records are inserted or deleted mid-traversal.

Use it with any `Fluent` model that exposes a `@ID` and an explicit
`sort`. Pass the `Databases` instance to your controller and query through it:

```swift
let page: CursorPaginator<User> = try await User.query(on: database)
    .sort(\.$id)
    .cursorPaginate(perPage: 20, on: req)

return page
```

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/studio-falkland/vapor-pagination", branch: "vapor5"),
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "VaporPagination", package: "vapor-pagination"),
    ]),
]
```

## API

`vapor-pagination` ships three value types and one `QueryBuilder` extension.

### `Cursor`

An opaque anchor for cursor-based pagination. Encodes the ordered-column
value of a row plus a `next` / `previous` direction as URL-safe base64
JSON so it can travel in a query string as `?cursor=...`.

| Member | Description |
|---|---|
| `init(points:values:)` | Build a cursor from a direction and a `[String: String]` of column → value. |
| `init?(from: String?)` | Decode a cursor from a query-string value. Returns `nil` for absent or malformed input. |
| `encoded() -> String` | JSON + URL-safe base64 encode. |
| `subscript(column:) -> String?` | Read a column's value off the cursor. |
| `points: .next` / `.previous` | Which way the cursor points. |

### `CursorPaginator<Element>`

A pure value type holding a page of items plus the metadata needed to
navigate forward and backward.

| Member | Description |
|---|---|
| `items` | Items on the current page. |
| `perPage` | Items per page. |
| `cursor` | The cursor this page was produced from. `nil` for the first page. |
| `hasMore` | Whether more items exist beyond this page. |
| `count` | Number of items on the current page. |
| `hasPages` | Whether there are enough items to split into multiple pages. |
| `hasMorePages` | Whether more items exist beyond this page. |
| `onFirstPage` / `onLastPage` | Position flags. |
| `nextCursor() / previousCursor() -> Cursor?` | Cursors for the next / previous page, derived from the order column. |
| `nextPageUrl() / previousPageUrl() -> String?` | Full URLs for the next / previous page, including any appended query parameters and the URL fragment. |
| `url(cursor:) -> String` | Build a URL for an arbitrary cursor instance. |
| `path` / `cursorName` / `query` / `fragment` | Inputs that drive URL construction. |

### `CursorPaginatedResponse<Element>`

A `Content`-conforming wrapper that turns a `CursorPaginator` into a JSON
response envelope with `data`, `links`, and `meta` keys:

```json
{
  "data": [ ... ],
  "links": { "next": "...", "previous": null },
  "meta": { "perPage": 15, "hasMorePages": true, "onFirstPage": true, "onLastPage": false, "cursor": "eyJwb2ludHMiOiJuZXh0Iiw..." }
}
```

| Method | Description |
|---|---|
| `makeResponse() -> CursorPaginatedResponse<Element>` | Converts the paginator into a response with the same element type. |
| `responding(with:) -> CursorPaginatedResponse<T>` | Maps items through a transform and returns a response with a different element type — ideal for DTOs. |

### `QueryBuilder.cursorPaginate(...)`

```swift
public func cursorPaginate(
    perPage: Int,
    on request: Request,
    orderColumn: String? = nil,
    cursorName: String = VaporPagination.defaultCursorName,
    baseURL: URL? = nil,
    keyForElement: @escaping (Model) -> String
) async throws -> CursorPaginator<Model>
```

Performs `WHERE col <op> value` + `LIMIT perPage + 1`, uses the extra row
to detect `hasMore`, and reverses the result in memory for backward
traversal. Single-column ordering for v1 — `orderColumn` defaults to
`"id"` (the model's `@ID`). The caller must declare the same sort
before invoking, e.g. `.sort(\$id)`.

| Parameter | Default | Description |
|---|---|---|
| `perPage` | — | Number of items per page. |
| `on` | — | The current HTTP request (reads the cursor from the query string). |
| `orderColumn` | `"id"` | Database column to order and cursor by. |
| `cursorName` | `"cursor"` | Query-string parameter name carrying the cursor. |
| `baseURL` | `nil` | Origin override for generated page URLs. Useful for direct TLS deployments. |
| `keyForElement` | Reads `model.id` | Closure that extracts the stringified cursor-anchor value from a model. **Required** when using a non-`id` order column. |

> **Note:** When `orderColumn` is `"id"` (the default), the library
> automatically extracts the model's ID value for the cursor — you
> don't need to pass `keyForElement`. For any other column you **must**
> provide a `keyForElement` closure (see the examples below).

For non-default order columns, pass the column name explicitly and provide
a `keyForElement` closure that extracts the cursor-anchor value from each
model. The closure must return a string representation that is
**lexicographically sortable** in the same order as the column:

```swift
// Ordering by a date column using ISO 8601 (lexicographically sortable):
try await Article.query(on: database)
    .filter(\.$published == true)
    .sort(\.$publishedAt, .ascending)
    .cursorPaginate(perPage: 20, on: req, orderColumn: "publishedAt") { article in
        // ISO 8601 round-trips through parseLiteral and is
        // lexicographically sortable.
        ISO8601DateFormatter().string(from: article.publishedAt)
    }

// Ordering by a date column using a Unix timestamp:
try await Article.query(on: database)
    .filter(\.$published == true)
    .sort(\.$publishedAt, .ascending)
    .cursorPaginate(perPage: 20, on: req, orderColumn: "publishedAt") { article in
        String(article.publishedAt.timeIntervalSince1970)
    }

// Ordering by a numeric column:
try await Product.query(on: database)
    .sort(\.$price, .ascending)
    .cursorPaginate(perPage: 20, on: req, orderColumn: "price") { product in
        String(product.price)
    }
```

The library's `parseLiteral` helper recognises `Int`, `UUID`, ISO 8601
dates, and Unix timestamps (as `Date`), and binds them with the correct
SQL type.

## Usage examples

### Returning a paginator directly

```swift
import Vapor
import VaporPagination

app.get("users") { req -> CursorPaginator<User> in
    try await User.query(on: database)
        .sort(\.$id)
        .cursorPaginate(perPage: 20, on: req)
}
```

### Returning a JSON envelope with `makeResponse()`

```swift
app.get("users") { req -> CursorPaginatedResponse<User> in
    try await User.query(on: database)
        .sort(\.$id)
        .cursorPaginate(perPage: 20, on: req)
        .makeResponse()
}
```

### Mapping to a DTO with `responding(with:)`

```swift
struct UserResponse: Content {
    let id: UUID?
    let displayName: String
}

app.get("users") { req -> CursorPaginatedResponse<UserResponse> in
    try await User.query(on: database)
        .sort(\.$id)
        .cursorPaginate(perPage: 20, on: req)
        .responding { user in
            UserResponse(id: user.id, displayName: user.name.capitalized)
        }
}
```

To use a custom cursor query-string parameter (e.g. for multiple
paginators on the same route):

```swift
try await Comment.query(on: database)
    .sort(\.$id)
    .cursorPaginate(perPage: 20, on: req, cursorName: "comments_cursor")
```

## Running tests

```bash
swift test
```

## Authors

![Studio Falkland](./Documentation/falkland-logo-long-orange.svg)

This library is brought to you by Studio Falkland and was developed by Lei Nelissen.

## License
This package is open-source software licensed under EUPL v1.2. See [LICENSE.md](LICENSE.md).
