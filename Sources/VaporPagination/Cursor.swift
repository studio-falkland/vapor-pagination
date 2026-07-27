import Foundation

/// An opaque anchor for cursor-based pagination.
///
/// Encodes the ordered-column value(s) of a row plus a direction
/// (`next` / `previous`). Transported in the query string as
/// `?cursor=<encoded>`.
public struct Cursor: Codable, Equatable {
    /// Which way to page from this cursor's anchor row.
    public enum Direction: String, Codable {
        case next
        case previous
    }

    /// The direction this cursor points.
    public let points: Direction

    /// Ordered-column name → stringified value for the anchor row.
    public let values: [String: String]

    public init(points: Direction, values: [String: String]) {
        self.points = points
        self.values = values
    }

    /// Look up a column's value for this cursor.
    public subscript(column: String) -> String? {
        values[column]
    }

    /// JSON + base64url encode for transport in a query string.
    ///
    /// Uses `.sortedKeys` so re-encoding a decoded cursor produces the
    /// same bytes as the original.
    public func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(self)) ?? Data()
        return data.base64URLEncodedString()
    }

    /// Decode from a query-string value. Returns nil when absent or
    /// malformed — an absent cursor means "first page".
    public init?(from queryString: String?) {
        guard let queryString, !queryString.isEmpty else { return nil }
        guard let data = Data(base64URLEncoded: queryString) else { return nil }
        guard let cursor = try? JSONDecoder().decode(Cursor.self, from: data) else { return nil }
        self = cursor
    }
}
