import Testing
import Foundation
@testable import VaporPagination

struct CursorTests {
    @Test
    func encodeDecodeRoundTrip() {
        let cursor = Cursor(points: .next, values: ["id": "15"])
        let encoded = cursor.encoded()
        #expect(!encoded.isEmpty)
        #expect(Cursor(from: encoded) == cursor)
    }

    @Test
    func roundTripPreservesDirectionAndValues() {
        let cursor = Cursor(points: .previous, values: ["id": "42", "ts": "1700000000"])
        let decoded = Cursor(from: cursor.encoded())
        #expect(decoded?.points == .previous)
        #expect(decoded?["id"] == "42")
        #expect(decoded?["ts"] == "1700000000")
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
        let b64 = Data(json.utf8).base64EncodedString()
        #expect(Cursor(from: b64) == nil)
    }

    @Test
    func subscriptLookup() {
        let cursor = Cursor(points: .previous, values: ["id": "42"])
        #expect(cursor["id"] == "42")
        #expect(cursor["missing"] == nil)
    }

    @Test
    func directionsAreDistinct() {
        let next = Cursor(points: .next, values: ["id": "1"])
        let prev = Cursor(points: .previous, values: ["id": "1"])
        #expect(next != prev)
    }

    @Test
    func encodedIsUrlSafe() {
        let encoded = Cursor(points: .next, values: ["id": "15"]).encoded()
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    @Test
    func reEncodingIsStable() {
        // Re-encoding a decoded cursor must produce the same bytes as the
        // original — required for `URL == URL` round-trips in paginators.
        let cursor = Cursor(points: .next, values: ["id": "1"])
        let once = cursor.encoded()
        let twice = Cursor(from: once)?.encoded()
        #expect(twice == once)
    }
}
