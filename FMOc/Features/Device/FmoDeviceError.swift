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
        case .localNetworkDenied: "本地网络访问已关闭"
        case .networkUnavailable: "当前网络不可用"
        case .discoveryTimedOut: "没有发现 FMO 设备"
        case .resolutionFailed: "无法解析设备地址"
        case .handshakeFailed: "无法建立 GEO 连接"
        case .disconnected: "FMO 连接已断开"
        case .responseTimedOut: "设备没有在 5 秒内响应"
        case .protocolViolation: "设备返回了无法识别的数据"
        case .unsupportedResponse: "设备返回了不支持的消息"
        case .invalidCoordinate: "坐标超出有效范围"
        case .deviceRejected: "FMO 拒绝了本次操作"
        case .operationCancelled: "操作已取消"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .localNetworkDenied: "请前往系统设置允许本地网络访问。"
        case .networkUnavailable: "请确认 iPhone 已连接 Wi-Fi。"
        case .discoveryTimedOut: "请确认盒子在同一 Wi-Fi，或手动输入 fmo.local。"
        case .resolutionFailed: "请尝试输入盒子的 IPv4 地址。"
        case .handshakeFailed, .disconnected, .responseTimedOut: "请确认盒子仍在线后重试。"
        case .protocolViolation, .unsupportedResponse, .deviceRejected: "请记录设备固件版本并打开连接诊断。"
        case .invalidCoordinate: "请重新获取位置后再同步。"
        case .operationCancelled: nil
        }
    }
}
