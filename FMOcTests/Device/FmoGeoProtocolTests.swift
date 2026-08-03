import Foundation
import Testing
@testable import FMOc

struct FmoGeoProtocolTests {
    private let protocolCodec = FmoGeoProtocol()

    @Test
    func encodesOfficialGetCoordinateRequest() throws {
        let request = try protocolCodec.makeGetCoordinateRequest()
        let object = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])

        #expect(object["type"] as? String == "config")
        #expect(object["subType"] as? String == "getCordinate")
        #expect(object["code"] as? Int == 0)
        #expect(object["data"] == nil)
    }

    @Test
    func encodesOfficialSetCoordinateRequest() throws {
        let coordinate = try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)
        let request = try protocolCodec.makeSetCoordinateRequest(coordinate)
        let object = try #require(JSONSerialization.jsonObject(with: request) as? [String: Any])
        let data = try #require(object["data"] as? [String: Any])

        #expect(object["subType"] as? String == "setCordinate")
        #expect(data["latitude"] as? Double == 31.2304)
        #expect(data["longitude"] as? Double == 121.4737)
    }

    @Test
    func decodesOfficialGetCoordinateResponse() throws {
        let fixture = Data(#"{"type":"config","subType":"getCordinateResponse","data":{"latitude":31.2304,"longitude":121.4737},"code":0}"#.utf8)

        let response = try protocolCodec.decodeResponse(fixture)
        #expect(response == .coordinate(try GeoCoordinate(latitude: 31.2304, longitude: 121.4737)))
    }

    @Test
    func decodesOfficialSetCoordinateResponse() throws {
        let fixture = Data(#"{"type":"config","subType":"setCordinateResponse","data":{"result":0},"code":0}"#.utf8)
        #expect(try protocolCodec.decodeResponse(fixture) == .coordinateSet)
    }

    @Test
    func mapsDeviceRejection() {
        let fixture = Data(#"{"type":"config","subType":"setCordinateResponse","data":{"result":-1},"code":0}"#.utf8)
        #expect(throws: FmoDeviceError.deviceRejected(code: -1)) {
            try protocolCodec.decodeResponse(fixture)
        }
    }

    @Test
    func rejectsUnknownAndMalformedResponses() {
        let unknown = Data(#"{"type":"config","subType":"futureResponse","code":0}"#.utf8)
        let malformed = Data(#"{"type":"config","subType":"getCordinateResponse","data":{"latitude":200,"longitude":0},"code":0}"#.utf8)

        #expect(throws: FmoDeviceError.unsupportedResponse) {
            try protocolCodec.decodeResponse(unknown)
        }
        #expect(throws: FmoDeviceError.protocolViolation) {
            try protocolCodec.decodeResponse(malformed)
        }
    }
}
