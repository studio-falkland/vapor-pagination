
import Foundation

/// A typed cursor-anchor value.
///
/// Cursors travel as JSON, so each value carries its own type. This lets the
/// query layer bind the value with the correct SQL type instead of guessing
/// from its string representation.
///
/// ```swift
/// Cursor(points: .next, values: [
///     "id": .uuid(user.id!),
///     "createdAt": .date(user.createdAt),
/// ])
/// ```
public enum CursorValue: Sendable, Equatable, Hashable {
    /// A text value.
    case string(String)

    /// A 64-bit integer value.
    case int(Int64)

    /// A floating-point value.
    case double(Double)

    /// A boolean value.
    case bool(Bool)

    /// A UUID value.
    case uuid(UUID)

    /// A date value.
    case date(Date)
}

public extension CursorValue {
    /// Convenience for `Int` values, which are widened to `Int64`.
    static func int(_ value: Int) -> CursorValue {
        .int(Int64(value))
    }
}

extension CursorValue: Codable {
    private enum Kind: Int, Codable {
        case string = 1
        case int = 2
        case double = 3
        case bool = 4
        case uuid = 5
        case date = 6
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        switch try container.decode(Kind.self) {
        case .string:
            self = .string(try container.decode(String.self))
        case .int:
            self = .int(try container.decode(Int64.self))
        case .double:
            self = .double(try container.decode(Double.self))
        case .bool:
            self = .bool(try container.decode(Bool.self))
        case .uuid:
            self = .uuid(try container.decode(UUID.self))
        case .date:
            self = .date(try container.decode(Date.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        switch self {
        case .string(let value):
            try container.encode(Kind.string)
            try container.encode(value)
        case .int(let value):
            try container.encode(Kind.int)
            try container.encode(value)
        case .double(let value):
            try container.encode(Kind.double)
            try container.encode(value)
        case .bool(let value):
            try container.encode(Kind.bool)
            try container.encode(value)
        case .uuid(let value):
            try container.encode(Kind.uuid)
            try container.encode(value)
        case .date(let value):
            try container.encode(Kind.date)
            try container.encode(value)
        }
    }
}
