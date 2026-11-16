import Foundation
import VaporUtilities

/// An opaque anchor for cursor-based pagination.
///
/// Encodes the ordered-column value(s) of a row plus a direction
/// (`next` / `previous`). Transported in the query string as
/// `?cursor=<encoded>`.
public struct Cursor: Codable, Equatable {
    /// Which way to page from this cursor's anchor row.
    public enum Direction: Int, Codable {
        case next = 0
        case previous = 1
    }

    /// The current cursor wire-format version.
    ///
    /// Cursors from an older or unknown version are rejected by
    /// ``init?(from:)`` and treated as "first page".
    public static let currentVersion = 2

    /// The cursor wire-format version.
    public let version: Int

    /// The direction this cursor points.
    public let points: Direction

    /// Ordered-column name → typed value for the anchor row.
    public let values: [String: CursorValue]

    public init(
        points: Direction,
        values: [String: CursorValue],
        version: Int = Cursor.currentVersion
    ) {
        self.version = version
        self.points = points
        self.values = values
    }

    /// Look up a column's value for this cursor.
    public subscript(column: String) -> CursorValue? {
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

    /// Decode from a query-string value. Returns nil when absent, malformed,
    /// or encoded with an unsupported version — an absent cursor means
    /// "first page".
    public init?(from queryString: String?) {
        guard let queryString, !queryString.isEmpty else { return nil }
        guard let data = Data(base64URLEncoded: queryString) else { return nil }
        guard let cursor = try? JSONDecoder().decode(Cursor.self, from: data) else { return nil }
        guard cursor.version == Cursor.currentVersion else { return nil }
        self = cursor
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.version = try container.decode(Int.self)
        self.points = try container.decode(Direction.self)
        self.values = try container.decode([String: CursorValue].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(self.version)
        try container.encode(self.points)
        try container.encode(self.values)
    }
}
