import Foundation

/// A single ordering term for cursor-based pagination.
///
/// Cursor pagination orders rows by one or more columns. Each `CursorOrder`
/// names a column and the direction it is sorted in. The position of a term
/// in the array is significant: it defines the lexicographic precedence used
/// to build the keyset predicate.
///
/// ```swift
/// let orders: [CursorOrder] = [
///     .ascending("lastName"),
///     .ascending("firstName"),
///     .descending("id"),
/// ]
/// ```
public struct CursorOrder: Sendable, Equatable, Hashable {
    /// The direction a column is sorted in.
    public enum Direction: String, Codable, Sendable, Hashable {
        case ascending
        case descending
    }

    /// The database column to order by.
    public let column: String

    /// The direction to sort the column in.
    public let direction: Direction

    public init(column: String, direction: Direction = .ascending) {
        self.column = column
        self.direction = direction
    }

    /// An ascending order term for `column`.
    public static func ascending(_ column: String) -> CursorOrder {
        CursorOrder(column: column, direction: .ascending)
    }

    /// A descending order term for `column`.
    public static func descending(_ column: String) -> CursorOrder {
        CursorOrder(column: column, direction: .descending)
    }
}
