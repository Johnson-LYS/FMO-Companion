import Foundation
import Testing
@testable import FMOc

struct FmoDeviceEndpointTests {
    @Test
    func buildsWebSocketURLWithResolvedPort() throws {
        let endpoint = try FmoDeviceEndpoint(host: "192.0.2.10", port: 8080, source: .bonjour)
        #expect(try endpoint.webSocketURL.absoluteString == "ws://192.0.2.10:8080/ws")
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
}
