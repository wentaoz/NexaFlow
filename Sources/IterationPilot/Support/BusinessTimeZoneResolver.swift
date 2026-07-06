import Foundation

enum BusinessTimeZoneResolver {
    static func resolve(
        timeZoneIdentifier: String?,
        countryRegion: String? = nil,
        businessBackground: String? = nil,
        businessSpaceName: String? = nil,
        fallback: String = TimeZone.current.identifier
    ) -> String {
        let explicit = timeZoneIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let joined = [explicit, countryRegion, businessBackground, businessSpaceName]
            .compactMap { $0?.nilIfBlank }
            .joined(separator: " ")
            .normalizedKey
        if isValidIANAIdentifier(explicit) {
            if let inferred = inferredIdentifier(from: joined),
               (explicit == TimeZone.current.identifier || isDefaultishIdentifier(explicit)) {
                return inferred
            }
            return explicit
        }

        if let inferred = inferredIdentifier(from: joined) {
            return inferred
        }

        return isValidIANAIdentifier(fallback) ? fallback : TimeZone.current.identifier
    }

    static func normalized(_ identifier: String, for space: BusinessSpace) -> String {
        resolve(
            timeZoneIdentifier: identifier,
            countryRegion: space.countryRegion,
            businessBackground: space.businessBackground,
            businessSpaceName: space.name,
            fallback: space.timeZoneIdentifier.nilIfBlank ?? TimeZone.current.identifier
        )
    }

    static func normalized(_ identifier: String, for snapshot: BusinessSpaceSnapshot) -> String {
        resolve(
            timeZoneIdentifier: identifier,
            countryRegion: snapshot.countryRegion,
            businessBackground: snapshot.businessBackground,
            businessSpaceName: snapshot.name,
            fallback: snapshot.timeZoneIdentifier.nilIfBlank ?? TimeZone.current.identifier
        )
    }

    private static func isValidIANAIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return TimeZone(identifier: value) != nil
    }

    private static func isDefaultishIdentifier(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "asia/shanghai" ||
            normalized == "etc/utc" ||
            normalized == "utc" ||
            normalized == "gmt"
    }

    private static func inferredIdentifier(from value: String) -> String? {
        if containsMexico(value) {
            return "America/Mexico_City"
        }
        if containsPhilippines(value) {
            return "Asia/Manila"
        }
        if containsColombia(value) {
            return "America/Bogota"
        }
        return nil
    }

    private static func containsMexico(_ value: String) -> Bool {
        value.contains("mexico") ||
            value.contains("méxico") ||
            value.contains("mexico city") ||
            value.contains("ciudad de mexico") ||
            value.contains("ciudad de méxico") ||
            value.contains("cdmx") ||
            value.contains("墨西哥") ||
            value == "mx" ||
            value.contains("_mx") ||
            value.contains("mx_")
    }

    private static func containsPhilippines(_ value: String) -> Bool {
        value.contains("philippines") ||
            value.contains("菲律宾") ||
            value == "ph" ||
            value.contains("_ph") ||
            value.contains("ph_")
    }

    private static func containsColombia(_ value: String) -> Bool {
        value.contains("colombia") ||
            value.contains("哥伦比亚") ||
            value == "co" ||
            value.contains("_co") ||
            value.contains("co_")
    }
}
