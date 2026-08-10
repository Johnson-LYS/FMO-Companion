import Foundation

nonisolated enum MaidenheadGrid {
    static func isValid(_ rawValue: String) -> Bool {
        let value = rawValue.uppercased()
        guard [4, 6, 8].contains(value.count) else { return false }
        let characters = Array(value)
        guard isLetter(characters[0], from: "A", through: "R"),
              isLetter(characters[1], from: "A", through: "R"),
              characters[2].isNumber,
              characters[3].isNumber else { return false }
        if value.count >= 6 {
            guard isLetter(characters[4], from: "A", through: "X"),
                  isLetter(characters[5], from: "A", through: "X") else { return false }
        }
        if value.count == 8 {
            guard characters[6].isNumber, characters[7].isNumber else { return false }
        }
        return true
    }

    static func center(of rawValue: String) -> GeoCoordinate? {
        let value = rawValue.uppercased()
        guard isValid(value) else { return nil }
        let characters = Array(value)
        guard let fieldLongitude = letterIndex(characters[0]),
              let fieldLatitude = letterIndex(characters[1]),
              let squareLongitude = characters[2].wholeNumberValue,
              let squareLatitude = characters[3].wholeNumberValue else { return nil }

        var longitude = -180 + Double(fieldLongitude * 20 + squareLongitude * 2)
        var latitude = -90 + Double(fieldLatitude * 10 + squareLatitude)
        var longitudeSize = 2.0
        var latitudeSize = 1.0

        if value.count >= 6,
           let subsquareLongitude = letterIndex(characters[4]),
           let subsquareLatitude = letterIndex(characters[5]) {
            longitude += Double(subsquareLongitude) / 12
            latitude += Double(subsquareLatitude) / 24
            longitudeSize = 1.0 / 12
            latitudeSize = 1.0 / 24
        }
        if value.count == 8,
           let extendedLongitude = characters[6].wholeNumberValue,
           let extendedLatitude = characters[7].wholeNumberValue {
            longitude += Double(extendedLongitude) / 120
            latitude += Double(extendedLatitude) / 240
            longitudeSize = 1.0 / 120
            latitudeSize = 1.0 / 240
        }
        return try? GeoCoordinate(
            latitude: latitude + latitudeSize / 2,
            longitude: longitude + longitudeSize / 2
        )
    }

    private static func isLetter(_ character: Character, from start: Character, through end: Character) -> Bool {
        character >= start && character <= end
    }

    private static func letterIndex(_ character: Character) -> Int? {
        guard let scalar = character.unicodeScalars.first else { return nil }
        return Int(scalar.value) - 65
    }
}
