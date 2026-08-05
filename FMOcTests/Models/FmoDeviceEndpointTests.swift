import Foundation
import Testing
@testable import FMOc

struct FmoDeviceEndpointTests {
    @Test
    func buildsWebSocketURLWithResolvedPort() throws {
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", port: 8080, source: .manual)
        #expect(try endpoint.webSocketURL.absoluteString == "ws://192.0.2.10:8080/ws")
        #expect(try endpoint.eventWebSocketURL.absoluteString == "ws://192.0.2.10:8080/events")
    }

    @Test
    func buildsOfficialManagementAndQsoURLs() throws {
        let endpoint = try FmoDeviceEndpoint(
            host: "192.0.2.10",
            port: 8080,
            source: .manual
        )

        #expect(
            try endpoint.officialWebURL(for: .management).absoluteString
                == "http://192.0.2.10:8080/"
        )
        #expect(
            try endpoint.officialWebURL(for: .qso).absoluteString
                == "http://192.0.2.10:8080/qso.html"
        )
    }

    @Test
    func officialWebURLUsesStableBonjourHostname() throws {
        let endpoint = try FmoDeviceEndpoint(
            host: "192.0.2.20%en0",
            source: .bonjour
        )

        #expect(
            try endpoint.officialWebURL(for: .management).absoluteString
                == "http://fmo.local/"
        )
    }

    @Test
    func usesStableHostnameForBonjourEndpoint() throws {
        let endpoint = try FmoDeviceEndpoint(
            host: "192.0.2.174%en0",
            port: 80,
            source: .bonjour,
            name: "FMO"
        )

        #expect(endpoint.host == "fmo.local")
        #expect(endpoint.port == nil)
        #expect(endpoint.displayAddress == "fmo.local")
        #expect(try endpoint.webSocketURL.absoluteString == "ws://fmo.local/ws")
    }

    @Test
    func rejectsURLsAndInvalidPortsInManualHostField() {
        #expect(throws: FmoDeviceEndpoint.ValidationError.unsupportedAddress) {
            try FmoDeviceEndpoint(host: "http://fmo.local", source: .manual)
        }
        #expect(throws: FmoDeviceEndpoint.ValidationError.invalidPort) {
            try FmoDeviceEndpoint(host: "fmo.local", port: 70_000, source: .manual)
        }
    }

    @Test
    func validatesPersistedEndpointDuringDecoding() {
        let invalid = Data(#"{"host":"http://fmo.local","port":80,"source":"manual"}"#.utf8)

        #expect(throws: FmoDeviceEndpoint.ValidationError.unsupportedAddress) {
            try JSONDecoder().decode(FmoDeviceEndpoint.self, from: invalid)
        }
    }

    @Test
    func migratesPreviouslyPersistedBonjourIP() throws {
        let legacy = Data(
            #"{"host":"192.0.2.174%en0","port":80,"source":"bonjour","name":"FMO"}"#.utf8
        )

        let endpoint = try JSONDecoder().decode(FmoDeviceEndpoint.self, from: legacy)
        #expect(endpoint.host == "fmo.local")
        #expect(endpoint.port == nil)
    }
}
