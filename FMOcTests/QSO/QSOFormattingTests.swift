import Foundation
import Testing
@testable import FMOc

struct QSOFormattingTests {
    @Test
    func decodesMaidenheadCentersWithoutPresentingPreciseCoordinates() throws {
        let center = try #require(MaidenheadGrid.center(of: "OM89AA"))
        #expect(center.latitude > 39 && center.latitude < 40)
        #expect(center.longitude > 116 && center.longitude < 118)
        #expect(MaidenheadGrid.center(of: "ZZ99ZZ") == nil)
    }

    @Test
    func exportsStandardADIFAndFMOExtensionsUsingUTF8ByteLengths() {
        let record = QSOCachedRecord(
            deviceID: "fmo.invalid:80",
            logID: 42,
            timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            fromCallsign: "BG0OWN",
            toCallsign: "BH0TST",
            fromGrid: "OM89AA",
            toGrid: "PM01AB",
            frequencyRaw: 1_458_000,
            mode: "FM",
            relayName: "测试",
            relayAdmin: "BG0ADM",
            comment: "73",
            hasDetail: true
        )
        let value = QSOADIFEncoder().encode([record])
        #expect(value.contains("<CALL:6>BH0TST"))
        #expect(value.contains("<GRIDSQUARE:6>PM01AB"))
        #expect(value.contains("<FREQ:8>145.8000"))
        #expect(value.contains("<APP_FMO_RELAY:6>测试"))
        #expect(value.contains("<EOR>"))
    }
}
