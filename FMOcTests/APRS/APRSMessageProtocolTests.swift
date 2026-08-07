import Testing
@testable import FMOc

struct APRSMessageProtocolTests {
    private let codec = APRSMessageCodec()

    @Test
    func encodesMessageWithNineCharacterAddresseeAndMessageID() throws {
        let line = try codec.encodePacket(
            source: TNC2Address(callsign: "BG5ESN", ssid: 11),
            addressee: TNC2Address(callsign: "BD7XYZ", ssid: 1),
            payload: .message(text: "HELLO", id: try APRSMessageID("A12"))
        )

        #expect(line == "BG5ESN-11>APFMO0,TCPIP*::BD7XYZ-1 :HELLO{A12")
    }

    @Test
    func usesFMOMessageProfileForNineByteTargetAndUTF8Text() throws {
        let line = try codec.encodePacket(
            source: TNC2Address(callsign: "BG0TST", ssid: 10),
            addressee: TNC2Address(callsign: "BG0TST", ssid: 15),
            payload: .message(text: "收到，73", id: try APRSMessageID("A15"))
        )

        #expect(line == "BG0TST-10>APFMO0,TCPIP*::BG0TST-15:收到，73{A15")

        let decoded = try codec.decode(
            TNC2PacketParser().parse(
                "BG0TST-15>APFMO0,qAC,T2TEST::BG0TST-10:收到，73{A15"
            ),
            expectedAddressee: TNC2Address(callsign: "BG0TST", ssid: 10)
        )
        #expect(decoded.payload == .message(text: "收到，73", id: try APRSMessageID("A15")))
    }

    @Test
    func decodesMessageAcknowledgementAndRejection() throws {
        let parser = TNC2PacketParser()
        let identity = TNC2Address(callsign: "BG5ESN", ssid: 11)

        let message = try codec.decode(
            parser.parse("BD7XYZ-1>APRS,TCPIP*::BG5ESN-11:HELLO{A12"),
            expectedAddressee: identity
        )
        let acknowledgement = try codec.decode(
            parser.parse("BD7XYZ-1>APRS,TCPIP*::BG5ESN-11:ackA12"),
            expectedAddressee: identity
        )
        let rejection = try codec.decode(
            parser.parse("BD7XYZ-1>APRS,TCPIP*::BG5ESN-11:rejA12"),
            expectedAddressee: identity
        )

        #expect(message.payload == .message(text: "HELLO", id: try APRSMessageID("A12")))
        #expect(acknowledgement.payload == .acknowledgement(try APRSMessageID("A12")))
        #expect(rejection.payload == .rejection(try APRSMessageID("A12")))
    }

    @Test
    func rejectsWrongAddresseeAndUnsupportedCharacters() throws {
        let packet = try TNC2PacketParser().parse("BD7XYZ-1>APRS::BG5ESN-11:HELLO{1")
        #expect(throws: APRSMessageProtocolError.wrongAddressee) {
            try codec.decode(
                packet,
                expectedAddressee: TNC2Address(callsign: "BG5ESN", ssid: 10)
            )
        }
        #expect(throws: APRSMessageProtocolError.unsupportedTextCharacter) {
            try codec.encodeInformation(
                addressee: TNC2Address(callsign: "BG5ESN", ssid: 10),
                payload: .message(text: "第一行\n第二行", id: nil)
            )
        }
        #expect(throws: APRSMessageProtocolError.unsupportedTextCharacter) {
            try codec.encodeInformation(
                addressee: TNC2Address(callsign: "BG5ESN", ssid: 10),
                payload: .message(text: "不能包含{", id: nil)
            )
        }
        #expect(throws: APRSMessageProtocolError.textTooLong) {
            try codec.encodeInformation(
                addressee: TNC2Address(callsign: "BG5ESN", ssid: 10),
                payload: .message(text: String(repeating: "测", count: 21), id: nil)
            )
        }
    }
}
