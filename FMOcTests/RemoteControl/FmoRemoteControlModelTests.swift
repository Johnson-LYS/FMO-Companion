import Foundation
import Testing
@testable import FMOc

@MainActor
struct FmoRemoteControlModelTests {
    @Test
    func rejectedRebootAuthenticationDoesNotConsumeCounterOrSend() async throws {
        let client = RemoteTestMessagingClient()
        let counter = RemoteTestCounterStore()
        let secretStore = RemoteTestSecretStore()
        let model = FmoRemoteControlModel(
            client: client,
            counterStore: counter,
            secretStore: secretStore,
            targetStore: RemoteTestTargetStore(),
            authenticator: RemoteTestAuthenticator(result: false),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        await model.setSource(try ReceiveOnlyAPRSIdentity(callsign: "BG5ESN", ssid: 10))
        model.setNetworkReady(true)
        #expect(await model.saveSettings(target: "BD7XYZ-1", secret: "ABCDEF123456"))

        await model.send(.reboot)

        #expect(await counter.callCount == 0)
        #expect(await client.sentPackets.isEmpty)
    }

    @Test
    func normalCommandSendsOnceAndAcceptsTargetControlAck() async throws {
        let client = RemoteTestMessagingClient()
        let counter = RemoteTestCounterStore()
        let model = FmoRemoteControlModel(
            client: client,
            counterStore: counter,
            secretStore: RemoteTestSecretStore(),
            targetStore: RemoteTestTargetStore(),
            authenticator: RemoteTestAuthenticator(result: true),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let source = try ReceiveOnlyAPRSIdentity(callsign: "BG5ESN", ssid: 10)
        let target = TNC2Address(callsign: "BD7XYZ", ssid: 1)
        await model.setSource(source)
        model.setNetworkReady(true)
        #expect(await model.saveSettings(target: target.formatted, secret: "ABCDEF123456"))

        await model.send(.normal)
        #expect(await client.sentPackets.count == 1)
        #expect(
            model.handleControlMessage(
                APRSMessageEnvelope(
                    source: target,
                    addressee: TNC2Address(callsign: source.callsign, ssid: source.ssid),
                    payload: .message(text: "ACK,CONTROL,NORMAL", id: nil)
                )
            )
        )
        #expect(model.phase == .confirmed(.normal))
    }
}

private actor RemoteTestMessagingClient: APRSISMessaging {
    private(set) var sentPackets: [String] = []

    func events(
        identity _: ReceiveOnlyAPRSIdentity,
        endpoint _: APRSISEndpoint
    ) -> AsyncThrowingStream<APRSISMessagingEvent, any Error> {
        AsyncThrowingStream { _ in }
    }

    func send(packet: String) { sentPackets.append(packet) }
    func disconnect() {}
}

private actor RemoteTestCounterStore: FmoRemoteControlCounterStoring {
    private(set) var callCount = 0

    func next(for _: TNC2Address, timeSlot: UInt64) -> FmoRemoteControlSequence {
        callCount += 1
        return FmoRemoteControlSequence(timeSlot: timeSlot, counter: 0)
    }
}

private actor RemoteTestSecretStore: FmoRemoteSecretStoring {
    private var values: [TNC2Address: String] = [:]

    func load(for target: TNC2Address) -> String? { values[target] }
    func save(_ secret: String, for target: TNC2Address) { values[target] = secret }
    func remove(for target: TNC2Address) { values[target] = nil }
}

private actor RemoteTestTargetStore: FmoRemoteTargetStoring {
    private var target: TNC2Address?
    func load() -> TNC2Address? { target }
    func save(_ target: TNC2Address) { self.target = target }
}

private struct RemoteTestAuthenticator: DeviceOwnerAuthenticating {
    let result: Bool
    func authorizeReboot() async -> Bool { result }
}
