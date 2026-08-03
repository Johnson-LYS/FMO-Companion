import Foundation

nonisolated struct GeoCoordinate: Codable, Hashable, Sendable {
    nonisolated enum ValidationError: Error, Equatable, Sendable {
        case nonFinite
        case latitudeOutOfRange
        case longitudeOutOfRange
    }

    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite else {
            throw ValidationError.nonFinite
        }
        guard (-90.0...90.0).contains(latitude) else {
            throw ValidationError.latitudeOutOfRange
        }
        guard (-180.0...180.0).contains(longitude) else {
            throw ValidationError.longitudeOutOfRange
        }

        self.latitude = latitude
        self.longitude = longitude
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        try self.init(latitude: latitude, longitude: longitude)
    }
}
