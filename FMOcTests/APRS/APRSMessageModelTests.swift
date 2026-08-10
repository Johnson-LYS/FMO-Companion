import Foundation
import SwiftData
import Testing
@testable import FMOc

@MainActor
struct APRSMessageModelTests {
    @Test
    func sendsPersistsAndMatchesAcknowledgement() async throws {
        let container = try ModelContainer(
            for: APRSMessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let client = ModelTestMessagingClient()
        let model = APRSMessageModel(
            client: client,
            policy: .init(retryDelay: .seconds(60), maximumRetryCount: 2)
        )
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG5ESN", ssid: 10)
        let peer = TNC2Address(callsign: "BD7XYZ", ssid: 1)
        model.configure(modelContext: container.mainContext)
        await model.setIdentity(identity)
        await model.setActive(true)
        await client.yield(.sessionReady(serverCallsign: "T2TEST"))
        await eventually { model.phase == .ready }

        #expect(await model.send(text: "HELLO", to: peer))
        let sent = await client.sentPackets()
        #expect(sent.count == 1)
        let records = try container.mainContext.fetch(FetchDescriptor<APRSMessageRecord>())
        let record = try #require(records.first)
        #expect(record.status == .waitingAcknowledgement)
        let messageID = try APRSMessageID(try #require(record.messageID))

        await client.yield(
            .message(
                APRSMessageEnvelope(
                    source: peer,
                    addressee: TNC2Address(callsign: identity.callsign, ssid: identity.ssid),
                    payload: .acknowledgement(messageID)
                )
            )
        )
        await eventually { record.status == .acknowledged }
        await model.setActive(false)
    }

    @Test
    func acceptsUTF8ButKeepsRejectedDraftOutOfHistory() async throws {
        let container = try ModelContainer(
            for: APRSMessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let client = ModelTestMessagingClient()
        let model = APRSMessageModel(client: client)
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG0TST", ssid: 10)
        let peer = TNC2Address(callsign: "BG0TST", ssid: 15)
        model.configure(modelContext: container.mainContext)
        await model.setIdentity(identity)
        await model.setActive(true)
        await client.yield(.sessionReady(serverCallsign: "T2TEST"))
        await eventually { model.phase == .ready }

        #expect(await model.send(text: "收到，73", to: peer))
        #expect(!(await model.send(text: "第一行\n第二行", to: peer)))

        let records = try container.mainContext.fetch(FetchDescriptor<APRSMessageRecord>())
        #expect(records.count == 1)
        #expect(records.first?.text == "收到，73")
        #expect(model.lastIssue == "消息不能包含换行或 { 符号")
        await model.setActive(false)
    }

    @Test
    func duplicateIncomingMessageIsStoredOnceButAcknowledgedEachTime() async throws {
        let container = try ModelContainer(
            for: APRSMessageRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let client = ModelTestMessagingClient()
        let model = APRSMessageModel(client: client)
        let identity = try ReceiveOnlyAPRSIdentity(callsign: "BG5ESN", ssid: 10)
        let peer = TNC2Address(callsign: "BD7XYZ", ssid: 1)
        let id = try APRSMessageID("123")
        model.configure(modelContext: container.mainContext)
        await model.setIdentity(identity)
        await model.setActive(true)
        await client.yield(.sessionReady(serverCallsign: "T2TEST"))
        await eventually { model.phase == .ready }
        let event = APRSISMessagingEvent.message(
            APRSMessageEnvelope(
                source: peer,
                addressee: TNC2Address(callsign: identity.callsign, ssid: identity.ssid),
                payload: .message(text: "HELLO", id: id)
            )
        )

        await client.yield(event)
        await client.yield(event)
        await eventually { await client.sentPackets().count == 2 }
        let records = try container.mainContext.fetch(FetchDescriptor<APRSMessageRecord>())
        #expect(records.count == 1)
        await model.setActive(false)
    }

    private func eventually(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0 ..< 100 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition was not met")
    }
}

private actor ModelTestMessagingClient: APRSISMessaging {
    private var continuation: AsyncThrowingStream<APRSISMessagingEvent, any Error>.Continuation?
    private var packets: [String] = []
    private var pendingEvents: [APRSISMessagingEvent] = []

    func events(
        identity _: ReceiveOnlyAPRSIdentity,
        endpoint _: APRSISEndpoint
    ) -> AsyncThrowingStream<APRSISMessagingEvent, any Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            pendingEvents.forEach { continuation.yield($0) }
            pendingEvents.removeAll()
        }
    }

    func send(packet: String) {
        packets.append(packet)
    }

    func disconnect() {
        continuation?.finish()
        continuation = nil
    }

    func yield(_ event: APRSISMessagingEvent) {
        if let continuation {
            continuation.yield(event)
        } else {
            pendingEvents.append(event)
        }
    }

    func sentPackets() -> [String] { packets }
}
