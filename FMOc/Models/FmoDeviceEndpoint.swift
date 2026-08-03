import Foundation

nonisolated struct FmoDeviceEndpoint: Codable, Hashable, Identifiable, Sendable {
    static let bonjourHost = "fmo.local"

    nonisolated enum Source: String, Codable, Sendable {
        case bonjour
        case manual
    }

    nonisolated enum ValidationError: Error, Equatable, Sendable {
        case emptyHost
        case invalidPort
        case unsupportedAddress
    }

    let host: String
    let port: Int?
    let source: Source
    let name: String?

    private enum CodingKeys: String, CodingKey {
        case host
        case port
        case source
        case name
    }

    var id: String { "\(host.lowercased()):\(port ?? 80)" }

    init(host: String, port: Int? = nil, source: Source, name: String? = nil) throws {
        let normalizedHost = source == .bonjour
            ? Self.bonjourHost
            : host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else { throw ValidationError.emptyHost }
        guard !normalizedHost.contains("://"),
              !normalizedHost.contains("/"),
              !normalizedHost.contains("?") else {
            throw ValidationError.unsupportedAddress
        }
        if let port, !(1...65_535).contains(port) {
            throw ValidationError.invalidPort
        }

        self.host = normalizedHost
        self.port = port == 80 ? nil : port
        self.source = source
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            host: container.decode(String.self, forKey: .host),
            port: container.decodeIfPresent(Int.self, forKey: .port),
            source: container.decode(Source.self, forKey: .source),
            name: container.decodeIfPresent(String.self, forKey: .name)
        )
    }

    var webSocketURL: URL {
        get throws {
            var components = URLComponents()
            components.scheme = "ws"
            components.host = host
            components.port = port
            components.path = "/ws"
            guard let url = components.url else { throw ValidationError.unsupportedAddress }
            return url
        }
    }

    var displayName: String { name ?? host }
    var displayAddress: String { port.map { "\(host):\($0)" } ?? host }
}
