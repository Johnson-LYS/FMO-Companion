import Foundation
import Testing
@testable import FMOc

struct FMOV4ParserTests {
    private let tnc2Parser = TNC2PacketParser()
    private let sut = FMOV4Parser()

    @Test
    func parsesActivityPositionFrame() throws {
        let frame = try parsePosition(
            "FMO-V4,VOCAL,CERT:\(certificate),S123,SIG:\(signature)"
        )
        let position = try requirePosition(frame)
        guard case let .activity(activity) = position.body else {
            Issue.record("Expected activity body")
            return
        }

        #expect(position.source == TNC2Address(callsign: "ZZ0TST", ssid: 15))
        #expect(position.latitudeText == "0000.00N")
        #expect(position.longitudeText == "00000.00E")
        #expect(position.symbolTable == "/")
        #expect(position.symbolCode == "i")
        #expect(activity == FMOV4Activity(type: .vocal, serverUID: 123))
        #expect(position.certificateBlob == Data(repeating: 0x01, count: 125))
        #expect(position.signature == Data(repeating: 0x02, count: 64))
    }

    @Test
    func parsesBeaconWithOrderedOptionalFields() throws {
        let frame = try parsePosition(
            "FMO-V4,BEACON,CERT:\(certificate),FREQ:438.5000,HEIGHT:15,RIG:FT-5DR,ANT:J型天线,SIG:\(signature)"
        )
        let position = try requirePosition(frame)
        guard case let .beacon(beacon) = position.body else {
            Issue.record("Expected beacon body")
            return
        }

        #expect(beacon.frequency == "438.5000")
        #expect(beacon.antennaHeight == 15)
        #expect(beacon.rigName == "FT-5DR")
        #expect(beacon.antennaName == "J型天线")
    }

    @Test
    func parsesStationFrame() throws {
        let frame = try parsePosition(
            "FMO-V4,STATION,CERT:\(certificate),CN,测试中继,fmo.example.com,P1883,F500KM,U5/200,SIG:\(signature)"
        )
        let position = try requirePosition(frame)
        guard case let .station(station) = position.body else {
            Issue.record("Expected station body")
            return
        }

        #expect(station.countryCode == "CN")
        #expect(station.name == "测试中继")
        #expect(station.host == "fmo.example.com")
        #expect(station.port == 1883)
        #expect(station.filterKilometers == 500)
        #expect(station.onlineUserCount == 5)
        #expect(station.peakUserCount == 200)
    }

    @Test
    func parsesJointPositionFrame() throws {
        let frame = try parsePosition(
            "FMO-V4,JOINT,CERT:\(certificate),SH:\(statusHash),SIG:\(signature)"
        )
        let position = try requirePosition(frame)
        guard case let .joint(hash) = position.body else {
            Issue.record("Expected joint body")
            return
        }

        #expect(hash == Data(repeating: 0x03, count: 32))
    }

    @Test
    func parsesEventContentIncludingCommas() throws {
        let packet = try tnc2Parser.parse(
            "ZZ0TST-15>APFMO4,TCPIP*:>FMO-V4,EVENT,12345,WeatherAlert,QTH now heavy rain,stay inside"
        )

        let frame = try sut.parse(packet)
        guard case let .event(event) = frame else {
            Issue.record("Expected event frame")
            return
        }

        #expect(event.uid == 12_345)
        #expect(event.topic == "WeatherAlert")
        #expect(event.content == "QTH now heavy rain,stay inside")
        #expect(
            event.rawStatusPayload
                == "FMO-V4,EVENT,12345,WeatherAlert,QTH now heavy rain,stay inside"
        )
    }

    @Test(arguments: [
        "ZZ0TST-15>APFM00,TCPIP*:=0000.00N/00000.00EiFMO-V4,CQ,CERT:x,S1,SIG:x",
        "ZZ0TST-15>APFMO4,qAS:=0000.00N/00000.00EiFMO-V4,CQ,CERT:x,S1,SIG:x",
        "ZZ0TST-15>APFMO4,TCPIP*:=9060.00N/00000.00EiFMO-V4,CQ,CERT:x,S1,SIG:x",
        "ZZ0TST-15>APFMO4,TCPIP*:=0000.00N/00000.00EiFMO-V4,UNKNOWN,CERT:x,S1,SIG:x",
    ])
    func rejectsFramesOutsideStrictFMOV4Boundary(_ line: String) throws {
        let packet = try tnc2Parser.parse(line)

        #expect(throws: FMOV4ParserError.self) {
            try sut.parse(packet)
        }
    }

    @Test
    func rejectsSignatureWithWrongDecodedLength() throws {
        let packet = try tnc2Parser.parse(
            "ZZ0TST-15>APFMO4,TCPIP*:=0000.00N/00000.00EiFMO-V4,CQ,CERT:\(certificate),S1,SIG:AQ"
        )

        #expect(throws: FMOV4ParserError.invalidSignature) {
            try sut.parse(packet)
        }
    }

    private func parsePosition(
        _ payload: String
    ) throws -> UnverifiedFMOV4Frame {
        let packet = try tnc2Parser.parse(
            "ZZ0TST-15>APFMO4,TCPIP*,qAS,T2TEST:=0000.00N/00000.00Ei\(payload)"
        )
        return try sut.parse(packet)
    }

    private func requirePosition(
        _ frame: UnverifiedFMOV4Frame
    ) throws -> UnverifiedFMOV4PositionFrame {
        guard case let .position(value) = frame else {
            throw TestError.unexpectedFrameType
        }
        return value
    }

    private var certificate: String {
        base64URL(Data(repeating: 0x01, count: 125))
    }

    private var signature: String {
        base64URL(Data(repeating: 0x02, count: 64))
    }

    private var statusHash: String {
        base64URL(Data(repeating: 0x03, count: 32))
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private enum TestError: Error {
        case unexpectedFrameType
    }
}
