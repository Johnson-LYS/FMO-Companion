import SwiftUI

enum AppTab: Hashable {
    case device
    case network
    case qso
    case settings
}

nonisolated enum DashboardViewportOrientation: Equatable, Sendable {
    case portrait
    case landscape

    init(size: CGSize) {
        self = size.width > size.height ? .landscape : .portrait
    }
}

enum DashboardHeroElement: Hashable {
    case container
    case callsign
    case maidenhead
    case filterDistance
    case server
    case speaker
}

enum DashboardHeroStage: Equatable {
    case presenting
    case rotatingToLandscape
    case expanded
    case rotatingToPortrait

    var showsExpandedContent: Bool {
        self == .rotatingToLandscape || self == .expanded
    }

    var activatesExpandedServices: Bool {
        self == .expanded
    }
}

struct DashboardHeroContext: Identifiable {
    let endpoint: FmoDeviceEndpoint
    let deviceName: String
    let initialDashboard: DashboardSnapshot

    var id: String { endpoint.id }
}

extension Animation {
    static var dashboardHero: Animation {
        .smooth(duration: 0.42, extraBounce: 0)
    }
}

extension View {
    @ViewBuilder
    func dashboardHeroSource(
        _ element: DashboardHeroElement,
        in namespace: Namespace.ID,
        isActive: Bool
    ) -> some View {
        if isActive {
            matchedGeometryEffect(
                id: element,
                in: namespace,
                properties: .frame,
                anchor: .leading,
                isSource: true
            )
        } else {
            self
        }
    }
}
