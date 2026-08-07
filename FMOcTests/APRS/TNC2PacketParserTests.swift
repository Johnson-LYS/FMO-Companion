import Testing
@testable import FMOc

struct TNC2PacketParserTests {
    private let sut = TNC2PacketParser()

    @Test
    func parsesFMOV4TNC2Packet() throws {
        let packet = try sut.parse(
            "zz0tst-15>apfmo4,TCPIP*,qAS,T2TEST:=0000.00N/00000.00EiFMO-V4,CQ"
        )

        #expect(packet.source == TNC2Address(callsign: "ZZ0TST", ssid: 15))
        #expect(packet.destination == "APFMO4")
        #expect(packet.path == ["TCPIP*", "QAS", "T2TEST"])
        #expect(packet.information.hasPrefix("=0000.00N/"))
    }

    @Test
    func parsesSourceWithoutSSIDAsZero() throws {
        let packet = try sut.parse("ZZ0TEST>APFMO4,TCPIP*:>FMO-V4,EVENT")

        #expect(packet.source.ssid == 0)
        #expect(packet.source.formatted == "ZZ0TEST")
    }

    @Test(arguments: [
        "# aprsc 2.1.19",
        "ZZ0TST-16>APFMO4,TCPIP*:payload",
        "ZZ0TST>APFMO4,TCPIP*:",
        "ZZ0TST>APFMO4,TCPIP*payload",
        "ZZ0TST>APFMO4,,TCPIP*:payload",
    ])
    func rejectsNonPacketOrMalformedPacket(_ line: String) {
        #expect(throws: TNC2PacketError.self) {
            try sut.parse(line)
        }
    }
}
