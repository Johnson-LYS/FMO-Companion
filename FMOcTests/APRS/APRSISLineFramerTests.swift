import Foundation
import Testing
@testable import FMOc

struct APRSISLineFramerTests {
    @Test
    func extractsFragmentedAndCoalescedCRLFLines() throws {
        var sut = APRSISLineFramer()

        #expect(try sut.append(Data("first\r".utf8)).isEmpty)
        #expect(
            try sut.append(Data("\nsecond\r\nthird".utf8))
                == ["first", "second"]
        )
        #expect(try sut.append(Data("\r\n".utf8)) == ["third"])
    }

    @Test
    func acceptsUTF8ContentWithoutCountingCharactersAsBytes() throws {
        var sut = APRSISLineFramer()

        let lines = try sut.append(Data("台站事件\r\n".utf8))

        #expect(lines == ["台站事件"])
    }

    @Test
    func acceptsExactly512BytesIncludingCRLF() throws {
        var sut = APRSISLineFramer()
        let line = String(repeating: "A", count: 510)

        #expect(try sut.append(Data("\(line)\r\n".utf8)) == [line])
    }

    @Test
    func rejectsLineLongerThan512BytesIncludingCRLF() {
        var sut = APRSISLineFramer()
        let line = String(repeating: "A", count: 511)

        #expect(throws: APRSISLineFramerError.lineTooLong) {
            try sut.append(Data("\(line)\r\n".utf8))
        }
    }

    @Test(arguments: ["line\n", "line\rX", "\r\n"])
    func rejectsInvalidLineBoundaries(_ input: String) {
        var sut = APRSISLineFramer()

        #expect(throws: APRSISLineFramerError.self) {
            try sut.append(Data(input.utf8))
        }
    }

    @Test
    func rejectsInvalidUTF8() {
        var sut = APRSISLineFramer()

        #expect(throws: APRSISLineFramerError.invalidUTF8) {
            try sut.append(Data([0xFF, 0x0D, 0x0A]))
        }
    }
}
