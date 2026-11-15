import FluentKit
import Foundation

/// In-memory model used by the cursor-pagination integration tests.
/// Has a single `@ID` and a single `name` field, matching the
/// single-column ordering assumption used by `cursorPaginate` v1.
final class TestUser: Model, @unchecked Sendable {
    static let schema = "test_users"

    @ID
    var id: UUID?

    @Field(key: "name")
    var name: String

    init() {}

    init(id: UUID? = nil, name: String) {
        self.id = id
        self.name = name
    }
}

struct CreateTestUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(TestUser.schema)
            .id()
            .field("name", .string, .required)
            .create()
    }
    func revert(on database: any Database) async throws {
        try await database.schema(TestUser.schema).delete()
    }
}
