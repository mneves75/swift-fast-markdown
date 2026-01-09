import Foundation

enum EntityDecoder {
    static func decode(_ entity: String) -> String {
        guard entity.hasPrefix("&"), entity.hasSuffix(";") else {
            return entity
        }

        if entity.hasPrefix("&#x") || entity.hasPrefix("&#X") {
            let hexStart = entity.index(entity.startIndex, offsetBy: 3)
            let hexEnd = entity.index(before: entity.endIndex)
            let hex = String(entity[hexStart..<hexEnd])
            if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                return String(scalar)
            }
            return entity
        }

        if entity.hasPrefix("&#") {
            let decStart = entity.index(entity.startIndex, offsetBy: 2)
            let decEnd = entity.index(before: entity.endIndex)
            let dec = String(entity[decStart..<decEnd])
            if let value = UInt32(dec, radix: 10), let scalar = UnicodeScalar(value) {
                return String(scalar)
            }
            return entity
        }

        return HTMLEntities.shared.lookup(entity) ?? entity
    }
}

struct HTMLEntities: Sendable {
    static let shared = HTMLEntities()

    private let entities: [String: String]

    private init() {
        self.entities = HTMLEntities.loadEntities()
    }

    func lookup(_ entity: String) -> String? {
        entities[entity]
    }

    private static func loadEntities() -> [String: String] {
        guard let url = Bundle.module.url(forResource: "HTMLEntities", withExtension: "json") else {
            #if DEBUG
            assertionFailure("[SwiftFastMarkdown] HTMLEntities.json not found in bundle")
            #endif
            return [:]
        }

        guard let data = try? Data(contentsOf: url) else {
            #if DEBUG
            assertionFailure("[SwiftFastMarkdown] Failed to read HTMLEntities.json")
            #endif
            return [:]
        }

        let decoded: [String: String]
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = json as? [String: Any] else {
                #if DEBUG
                assertionFailure("[SwiftFastMarkdown] HTMLEntities.json has unexpected format")
                #endif
                return [:]
            }

            var output: [String: String] = [:]
            output.reserveCapacity(dict.count)
            for (key, value) in dict {
                guard let entry = value as? [String: Any],
                      let characters = entry["characters"] as? String else {
                    continue
                }
                output[key] = characters
            }
            decoded = output
        } catch {
            #if DEBUG
            assertionFailure("[SwiftFastMarkdown] Failed to parse HTMLEntities.json: \(error)")
            #endif
            return [:]
        }

        return decoded
    }
}
