import Testing
import Foundation
import VaporUtilities
@testable import VaporPagination

struct CursorTests {
    @Test
    func encodeDecodeRoundTrip() {
        let cursor = Cursor(points: .next, values: ["id": .int(15)])
        let encoded = cursor.encoded()
        #expect(!encoded.isEmpty)
        #expect(Cursor(from: encoded) == cursor)
    }

    @Test
    func roundTripPreservesDirectionAndValues() {
        let cursor = Cursor(points: .previous, values: ["id": .int(42), "ts": .int(1_700_000_000)])
        let decoded = Cursor(from: cursor.encoded())
        #expect(decoded?.points == .previous)
        #expect(decoded?["id"] == .int(42))
        #expect(decoded?["ts"] == .int(1_700_000_000))
    }

    @Test
    func typedValuesRoundTrip() {
        let uuid = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let cursor = Cursor(points: .next, values: [
            "string": .string("hello"),
            "int": .int(42),
            "double": .double(1.5),
            "bool": .bool(true),
            "uuid": .uuid(uuid),
            "date": .date(date),
        ])

        let decoded = Cursor(from: cursor.encoded())
        #expect(decoded == cursor)
        #expect(decoded?["string"] == .string("hello"))
        #expect(decoded?["int"] == .int(42))
        #expect(decoded?["double"] == .double(1.5))
        #expect(decoded?["bool"] == .bool(true))
        #expect(decoded?["uuid"] == .uuid(uuid))
        #expect(decoded?["date"] == .date(date))
    }

    @Test
    func initFromNilReturnsNil() {
        #expect(Cursor(from: nil) == nil)
    }

    @Test
    func initFromEmptyReturnsNil() {
        #expect(Cursor(from: "") == nil)
    }

    @Test
    func initFromMalformedReturnsNil() {
        #expect(Cursor(from: "!!!not-base64!!!") == nil)
    }

    @Test
    func initFromValidBase64NonCursorJsonReturnsNil() {
        let json = #"{"foo":"bar"}"#
        #expect(Cursor(from: json.base64URLEncodedString()) == nil)
    }

    @Test
    func rejectsLegacyStringValuedCursor() {
        // The pre-typed format stored values as plain strings.
        let json = #"{"points":"next","values":{"id":"15"}}"#
        #expect(Cursor(from: json.base64URLEncodedString()) == nil)
    }

    @Test
    func rejectsUnknownVersion() {
        let cursor = Cursor(points: .next, values: ["id": .int(1)], version: 99)
        #expect(Cursor(from: cursor.encoded()) == nil)
    }

    @Test
    func subscriptLookup() {
        let cursor = Cursor(points: .previous, values: ["id": .int(42)])
        #expect(cursor["id"] == .int(42))
        #expect(cursor["missing"] == nil)
    }

    @Test
    func directionsAreDistinct() {
        let next = Cursor(points: .next, values: ["id": .int(1)])
        let prev = Cursor(points: .previous, values: ["id": .int(1)])
        #expect(next != prev)
    }

    @Test
    func encodedIsUrlSafe() {
        let encoded = Cursor(points: .next, values: ["id": .int(15)]).encoded()
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    @Test
    func reEncodingIsStable() {
        // Re-encoding a decoded cursor must produce the same bytes as the
        // original — required for `URL == URL` round-trips in paginators.
        let cursor = Cursor(points: .next, values: ["id": .int(1)])
        let once = cursor.encoded()
        let twice = Cursor(from: once)?.encoded()
        #expect(twice == once)
    }
}
