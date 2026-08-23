import Foundation
import Opus

nonisolated enum FMOAudioCodecError: Error, Equatable, Sendable {
    case initializationFailed(Int32)
    case invalidPCMFrame
    case encodeFailed(Int32)
    case decodeFailed(Int32)
}

protocol FMOAudioCodec: Sendable {
    func encode40ms(_ pcm: [Int16]) async throws -> Data
    func decode40ms(_ data: Data) async throws -> [Int16]
    func concealLoss() async throws -> [Int16]
    func reset() async throws
}

nonisolated final class LibOpusCodec: FMOAudioCodec, @unchecked Sendable {
    private var encoder: OpaquePointer
    private var decoder: OpaquePointer
    private let lock = NSLock()

    init() throws {
        var error: Int32 = OPUS_OK
        guard let encoder = opus_encoder_create(8_000, 1, OPUS_APPLICATION_VOIP, &error) else {
            throw FMOAudioCodecError.initializationFailed(error)
        }
        error = fmo_opus_configure_voice_encoder(encoder)
        guard error == OPUS_OK else {
            opus_encoder_destroy(encoder)
            throw FMOAudioCodecError.initializationFailed(error)
        }
        guard let decoder = opus_decoder_create(8_000, 1, &error) else {
            opus_encoder_destroy(encoder)
            throw FMOAudioCodecError.initializationFailed(error)
        }
        self.encoder = encoder
        self.decoder = decoder
    }

    deinit {
        opus_encoder_destroy(encoder)
        opus_decoder_destroy(decoder)
    }

    func encode40ms(_ pcm: [Int16]) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard pcm.count == 320 else { throw FMOAudioCodecError.invalidPCMFrame }
        var output = [UInt8](repeating: 0, count: 1_276)
        let length = pcm.withUnsafeBufferPointer { samples in
            guard let baseAddress = samples.baseAddress else { return OPUS_BAD_ARG }
            return opus_encode(encoder, baseAddress, 320, &output, Int32(output.count))
        }
        guard length >= 0 else { throw FMOAudioCodecError.encodeFailed(length) }
        return Data(output.prefix(Int(length)))
    }

    func decode40ms(_ data: Data) throws -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        guard !data.isEmpty else { throw FMOAudioCodecError.decodeFailed(OPUS_BAD_ARG) }
        var output = [Int16](repeating: 0, count: 320)
        let count = data.withUnsafeBytes { bytes in
            opus_decode(
                decoder,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                Int32(data.count),
                &output,
                320,
                0
            )
        }
        guard count >= 0 else { throw FMOAudioCodecError.decodeFailed(count) }
        if count < 320 { output.removeSubrange(Int(count) ..< output.count) }
        return output
    }

    func concealLoss() throws -> [Int16] {
        lock.lock()
        defer { lock.unlock() }
        var output = [Int16](repeating: 0, count: 320)
        let count = opus_decode(decoder, nil, 0, &output, 320, 0)
        guard count >= 0 else { throw FMOAudioCodecError.decodeFailed(count) }
        return output
    }

    func reset() throws {
        lock.lock()
        defer { lock.unlock() }
        var error: Int32 = OPUS_OK
        guard let newEncoder = opus_encoder_create(8_000, 1, OPUS_APPLICATION_VOIP, &error) else {
            throw FMOAudioCodecError.initializationFailed(error)
        }
        error = fmo_opus_configure_voice_encoder(newEncoder)
        guard error == OPUS_OK else {
            opus_encoder_destroy(newEncoder)
            throw FMOAudioCodecError.initializationFailed(error)
        }
        guard let newDecoder = opus_decoder_create(8_000, 1, &error) else {
            opus_encoder_destroy(newEncoder)
            throw FMOAudioCodecError.initializationFailed(error)
        }
        opus_encoder_destroy(encoder)
        opus_decoder_destroy(decoder)
        encoder = newEncoder
        decoder = newDecoder
    }
}
