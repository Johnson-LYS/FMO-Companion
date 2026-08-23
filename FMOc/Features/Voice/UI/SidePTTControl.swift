import SwiftUI

struct SidePTTControl: View {
    @Bindable var model: DirectVoiceSessionModel
    var isFullscreen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPressing = false

    var body: some View {
        HStack(spacing: 7) {
            handle
            if model.isPTTExpanded {
                expandedPanel
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, 8)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.34, bounce: 0.16), value: model.isPTTExpanded)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                isPressing = false
                model.sceneBecameInactive()
            }
        }
    }

    private var handle: some View {
        Button {
            if isPressing { model.endTransmit(); isPressing = false }
            model.isPTTExpanded.toggle()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "mic.fill")
                    .font(.caption.bold())
                Text("PTT")
                    .font(.caption2.bold())
                    .rotationEffect(.degrees(90))
            }
            .foregroundStyle(Color(red: 0.065, green: 0.07, blue: 0.085))
            .frame(width: 46, height: isFullscreen ? 82 : 74)
            .background(Color.accentColor, in: .rect(cornerRadii: .init(topLeading: 20, bottomLeading: 20)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPTTExpanded ? String(localized: "收起 PTT") : String(localized: "展开 PTT"))
        .accessibilityValue(phaseLabel)
        .accessibilityIdentifier(isFullscreen ? "fullscreen-side-ptt" : "home-side-ptt")
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "此 iPhone · \(model.identity?.callsign ?? String(localized: "未配置"))"))
                .font(.caption2.bold())
                .foregroundStyle(isFullscreen ? .white.opacity(0.68) : .secondary)
                .lineLimit(1)

            VStack(spacing: 7) {
                Image(systemName: isTransmitting ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: isFullscreen ? 38 : 32, weight: .bold))
                Text(isTransmitting ? String(localized: "正在发射") : String(localized: "按住发射"))
                    .font((isFullscreen ? Font.title3 : .headline).bold())
                Text(isTransmitting ? String(localized: "松手立即停止") : phaseLabel)
                    .font(.caption2)
                    .opacity(0.72)
            }
            .foregroundStyle(isTransmitting ? Color.white : Color(red: 0.065, green: 0.07, blue: 0.085))
            .frame(width: isFullscreen ? 182 : 164, height: isFullscreen ? 148 : 126)
            .background(isTransmitting ? Color(uiColor: .systemRed) : Color.accentColor)
            .clipShape(.rect(cornerRadii: .init(topLeading: 28, bottomLeading: 28)))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        model.beginTransmit()
                    }
                    .onEnded { _ in
                        guard isPressing else { return }
                        isPressing = false
                        model.endTransmit()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("按住发射")
            .accessibilityValue(isTransmitting ? String(localized: "正在发射，松手停止") : phaseLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("direct-voice-ptt-button")
        }
        .accessibilityIdentifier("direct-voice-ptt-panel")
    }

    private var isTransmitting: Bool {
        if case .transmitting = model.snapshot.phase { return true }
        return false
    }

    private var phaseLabel: String {
        switch model.snapshot.phase {
        case .idle: String(localized: "未连接")
        case .connecting: String(localized: "正在连接")
        case .listening: String(localized: "监听中")
        case .receiving(let callsign): String(localized: "正在接收 \(callsign)")
        case .transmitting: String(localized: "正在发射")
        case .busy: String(localized: "通道繁忙")
        case .failed(let message): message
        }
    }
}
