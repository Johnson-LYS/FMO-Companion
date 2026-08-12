import Foundation
import Testing
@testable import FMOc

struct DashboardSpeakerLocationStoreTests {
    @Test
    func persistsCoordinateGridAndAreaAcrossStoreInstances() async throws {
        let suite = "DashboardSpeakerLocationStoreTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)

        await UserDefaultsDashboardSpeakerLocationStore(suiteName: suite).save(
            DashboardSpeakerLocation(
                callsign: "bg4abc",
                coordinate: coordinate,
                grid: "PM01RF",
                areaName: "中国上海市",
                updatedAt: savedAt
            )
        )

        let restored = await UserDefaultsDashboardSpeakerLocationStore(suiteName: suite)
            .location(for: "BG4ABC")
        #expect(restored == DashboardSpeakerLocation(
            callsign: "BG4ABC",
            coordinate: coordinate,
            grid: "PM01RF",
            areaName: "中国上海市",
            updatedAt: savedAt
        ))
    }

    @Test
    func restoresCachedCoordinateWhenReconnectHistoryHasNoGrid() async throws {
        let locationStore = VolatileDashboardSpeakerLocationStore()
        let coordinate = try GeoCoordinate(latitude: 39.9042, longitude: 116.4074)
        await locationStore.save(
            DashboardSpeakerLocation(
                callsign: "BG1AAA",
                coordinate: coordinate,
                grid: "OM89AA",
                areaName: "中国北京市",
                updatedAt: .now
            )
        )
        let dashboardStore = DashboardStore(speakerLocationStore: locationStore)

        let snapshot = await dashboardStore.recordLocalEvent(
            .history([
                FmoRecentLocalActivity(callsign: "BG1AAA", occurredAt: .now)
            ])
        )

        #expect(snapshot.recentLocalActivities.first?.grid == "OM89AA")
        #expect(snapshot.recentLocalActivities.first?.coordinate == coordinate)
    }
}
