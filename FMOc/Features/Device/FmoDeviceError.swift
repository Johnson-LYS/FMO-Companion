import Foundation

nonisolated enum FmoDeviceError: Error, Equatable, Sendable {
    case localNetworkDenied
    case networkUnavailable
    case discoveryTimedOut
    case resolutionFailed
    case handshakeFailed
    case disconnected
    case responseTimedOut
    case protocolViolation
    case unsupportedResponse
    case invalidCoordinate
    case deviceRejected(code: Int)
    case operationCancelled
}

extension FmoDeviceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .localNetworkDenied: String(localized: "本地网络访问已关闭")
        case .networkUnavailable: String(localized: "当前网络不可用")
        case .discoveryTimedOut: String(localized: "没有发现 FMO 设备")
        case .resolutionFailed: String(localized: "无法解析设备地址")
        case .handshakeFailed: String(localized: "无法建立 GEO 连接")
        case .disconnected: String(localized: "FMO 连接已断开")
        case .responseTimedOut: String(localized: "设备没有在 5 秒内响应")
        case .protocolViolation: String(localized: "设备返回了无法识别的数据")
        case .unsupportedResponse: String(localized: "设备返回了不支持的消息")
        case .invalidCoordinate: String(localized: "坐标超出有效范围")
        case .deviceRejected: String(localized: "FMO 拒绝了本次操作")
        case .operationCancelled: String(localized: "操作已取消")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .localNetworkDenied: String(localized: "请前往系统设置允许本地网络访问。")
        case .networkUnavailable: String(localized: "请确认 iPhone 已连接 Wi-Fi。")
        case .discoveryTimedOut: String(localized: "请确认盒子在同一 Wi-Fi，或手动输入 fmo.local。")
        case .resolutionFailed: String(localized: "请尝试输入盒子的 IPv4 地址。")
        case .handshakeFailed, .disconnected, .responseTimedOut: String(localized: "请确认盒子仍在线后重试。")
        case .protocolViolation, .unsupportedResponse, .deviceRejected: String(localized: "请记录设备固件版本并打开连接诊断。")
        case .invalidCoordinate: String(localized: "请重新获取位置后再同步。")
        case .operationCancelled: nil
        }
    }
}
