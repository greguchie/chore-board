import Foundation

nonisolated enum JSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let jsonDecoder = JSONDecoder()
        // The API sends "2026-10-28T19:38:50.214Z". Swift's built-in .iso8601
        // rejects the milliseconds, so try with them first, then without.
        jsonDecoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(text) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date: \(text)")
        }
        return jsonDecoder
    }

    static func makeEncoder() -> JSONEncoder {
        JSONEncoder()
    }
}
