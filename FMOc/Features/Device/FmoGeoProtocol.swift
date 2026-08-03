import Foundation

nonisolated struct FmoGeoProtocol: Sendable {
    nonisolated enum Response: Equatable, Sendable {
        case coordinate(GeoCoordinate)
        case coordinateSet
    }

    private struct Envelope<DataValue: Codable & Sendable>: Codable, Sendable {
        let type: String
        let subType: String
        let data: DataValue?
        let code: Int
    }

    private struct EmptyData: Codable, Sendable {}

    private struct SetCoordinateData: Codable, Sendable {
        let latitude: Double
        let longitude: Double
    }

    private struct SetCoordinateResponseData: Codable, Sendable {
        let result: Int
    }

    private struct ResponseHeader: Decodable, Sendable {
        let type: String
        let subType: String
        let code: Int
    }

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func makeGetCoordinateRequest() throws -> Data {
        try encoder.encode(
            Envelope<EmptyData>(type: "config", subType: "getCordinate", data: nil, code: 0)
        )
    }

    func makeSetCoordinateRequest(_ coordinate: GeoCoordinate) throws -> Data {
        try encoder.encode(
            Envelope(
                type: "config",
                subType: "setCordinate",
                data: SetCoordinateData(latitude: coordinate.latitude, longitude: coordinate.longitude),
                code: 0
            )
        )
    }

    func decodeResponse(_ data: Data) throws -> Response {
        let header: ResponseHeader
        do {
            header = try decoder.decode(ResponseHeader.self, from: data)
        } catch {
            throw FmoDeviceError.protocolViolation
        }

        guard header.type == "config" else { throw FmoDeviceError.protocolViolation }
        guard header.code == 0 else { throw FmoDeviceError.deviceRejected(code: header.code) }

        switch header.subType {
        case "getCordinateResponse":
            do {
                let envelope = try decoder.decode(Envelope<GeoCoordinate>.self, from: data)
                guard let coordinate = envelope.data else { throw FmoDeviceError.protocolViolation }
                return .coordinate(coordinate)
            } catch let error as FmoDeviceError {
                throw error
            } catch {
                throw FmoDeviceError.protocolViolation
            }

        case "setCordinateResponse":
            do {
                let envelope = try decoder.decode(Envelope<SetCoordinateResponseData>.self, from: data)
                guard let response = envelope.data else { throw FmoDeviceError.protocolViolation }
                guard response.result == 0 else {
                    throw FmoDeviceError.deviceRejected(code: response.result)
                }
                return .coordinateSet
            } catch let error as FmoDeviceError {
                throw error
            } catch {
                throw FmoDeviceError.protocolViolation
            }

        default:
            throw FmoDeviceError.unsupportedResponse
        }
    }
}
