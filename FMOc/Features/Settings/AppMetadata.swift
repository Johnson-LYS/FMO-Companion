import Foundation

struct AppMetadata: Equatable {
    let name: String
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? String(localized: "FMO 助手")
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    var versionDescription: String {
        guard !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}

enum AppLinks {
    static let developerCallsign = "BI8SYN"
    static let contactEmail = "BI8SYN@163.com"

    static var contactURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = contactEmail
        components.queryItems = [URLQueryItem(name: "subject", value: String(localized: "FMO 助手反馈"))]
        return components.url!
    }

    static var privacyPolicyURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "FMOPrivacyPolicyURL") as? String,
            let url = URL(string: value),
            url.scheme?.lowercased() == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }
}
