import Foundation
import Testing
@testable import FMOc

struct GeoCoordinateTests {
    @Test(arguments: [
        (-90.0, -180.0),
        (0.0, 0.0),
        (90.0, 180.0),
    ])
    func acceptsBoundaryCoordinates(latitude: Double, longitude: Double) throws {
        let coordinate = try GeoCoordinate(latitude: latitude, longitude: longitude)
        #expect(coordinate.latitude == latitude)
        #expect(coordinate.longitude == longitude)
    }

    @Test(arguments: [
        (91.0, 0.0, GeoCoordinate.ValidationError.latitudeOutOfRange),
        (0.0, 181.0, GeoCoordinate.ValidationError.longitudeOutOfRange),
        (.infinity, 0.0, GeoCoordinate.ValidationError.nonFinite),
        (0.0, .nan, GeoCoordinate.ValidationError.nonFinite),
    ])
    func rejectsInvalidCoordinates(
        latitude: Double,
        longitude: Double,
        expectedError: GeoCoordinate.ValidationError
    ) {
        #expect(throws: expectedError) {
            try GeoCoordinate(latitude: latitude, longitude: longitude)
        }
    }
}
