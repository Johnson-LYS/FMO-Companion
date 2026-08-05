import Foundation

nonisolated enum MaidenheadLocator {
    static func sixCharacterGrid(for coordinate: GeoCoordinate) -> String {
        // 正向边界属于最后一个网格；先平移再夹紧，避免 nextDown 在加法后重新舍入到区间外。
        let adjustedLongitude = min(coordinate.longitude + 180, 360.0.nextDown)
        let adjustedLatitude = min(coordinate.latitude + 90, 180.0.nextDown)

        let longitudeField = Int(adjustedLongitude / 20)
        let latitudeField = Int(adjustedLatitude / 10)
        let longitudeSquare = Int(adjustedLongitude.truncatingRemainder(dividingBy: 20) / 2)
        let latitudeSquare = Int(adjustedLatitude.truncatingRemainder(dividingBy: 10))
        let longitudeSubsquare = Int(adjustedLongitude.truncatingRemainder(dividingBy: 2) * 12)
        let latitudeSubsquare = Int(adjustedLatitude.truncatingRemainder(dividingBy: 1) * 24)

        return String([
            uppercaseLetter(at: longitudeField),
            uppercaseLetter(at: latitudeField),
            Character(String(longitudeSquare)),
            Character(String(latitudeSquare)),
            lowercaseLetter(at: longitudeSubsquare),
            lowercaseLetter(at: latitudeSubsquare),
        ])
    }

    private static func uppercaseLetter(at offset: Int) -> Character {
        Character(UnicodeScalar(65 + offset)!)
    }

    private static func lowercaseLetter(at offset: Int) -> Character {
        Character(UnicodeScalar(97 + offset)!)
    }
}
