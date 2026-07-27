import Testing
@testable import VaporPagination

struct VaporPaginationTests {
    @Test
    func defaultCursorName() {
        #expect(VaporPagination.defaultCursorName == "cursor")
    }
}
