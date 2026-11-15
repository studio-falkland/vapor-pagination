import Foundation
import Vapor
import VaporUtilities

/// A minimal `Decodable` mirror of the request's query string that
/// flattens top-level pairs into a `[String: String]`. Decoded via
/// Vapor's `URLEncodedFormDecoder`, the framework's canonical
/// query-string parser.
private struct FlatQuery: Decodable {
    var values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var result: [String: String] = [:]
        for key in container.allKeys {
            if let s = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = s
            } else {
                result[key.stringValue] = ""
            }
        }
        self.values = result
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }
}

extension Request {
    /// Returns the request's full origin + path, suitable for use as
    /// the `path` field of a `CursorPaginator`.
    ///
    /// Built from `VaporUtilities`'s ``Request/absoluteURL(baseURL:)``, which
    /// resolves the origin from the forwarded headers, the `Host` header, or
    /// the local address. The query and fragment are dropped.
    ///
    /// - Parameter baseURL: An optional origin override.
    /// - Returns: The origin and path, without the query or fragment.
    func paginationPath(baseURL: URL? = nil) -> String {
        let url = self.absoluteURL(baseURL: baseURL)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString
        }
        components.query = nil
        components.fragment = nil
        return components.string ?? url.absoluteString
    }

    /// Returns the request's query parameters as a flat dictionary,
    /// excluding the named cursor parameter so it can be re-emitted
    /// inside pagination URLs without duplicating the cursor itself.
    /// Decoded via Vapor's `URLEncodedFormDecoder`, the canonical
    /// query-string parser in the framework.
    func appendedQuery(excluding name: String) -> [String: String] {
        let decoder = URLEncodedFormDecoder()
        guard let query = try? decoder.decode(FlatQuery.self, from: self.url) else {
            return [:]
        }
        return query.values.filter { $0.key != name }
    }
}
