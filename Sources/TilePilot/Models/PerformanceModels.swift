import Foundation

enum PerformancePreset: String, CaseIterable, Codable, Sendable {
    case balanced
    case responsive
    case passiveBaseline
    case lowCPU
    case custom

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .responsive: return "Responsive"
        case .passiveBaseline: return "Passive Baseline"
        case .lowCPU: return "Low CPU"
        case .custom: return "Custom"
        }
    }

    static var selectableCases: [PerformancePreset] {
        [.balanced, .responsive, .passiveBaseline, .lowCPU]
    }
}

enum PerformanceDegradationMode: String, Codable, Sendable, Equatable {
    case full
    case reducedOverlayResponsiveness
    case reducedKeepOnTopResponsiveness
    case degradedPolling

    var title: String {
        switch self {
        case .full:
            return "Full"
        case .reducedOverlayResponsiveness:
            return "Reduced Overlay Responsiveness"
        case .reducedKeepOnTopResponsiveness:
            return "Reduced Keep-on-Top Responsiveness"
        case .degradedPolling:
            return "Degraded Polling"
        }
    }

    var detail: String? {
        switch self {
        case .full:
            return nil
        case .reducedOverlayResponsiveness:
            return "Badges and outlines may follow windows more slowly, and overview refreshes may animate less, to reduce CPU."
        case .reducedKeepOnTopResponsiveness:
            return "Keep-on-top may react more slowly to reduce CPU."
        case .degradedPolling:
            return "Background state refresh is intentionally slower to reduce CPU."
        }
    }
}

enum OverlayRefreshPolicy: String, Codable, Sendable, Equatable {
    case full
    case reduced
}

struct PerformanceSettings: Codable, Sendable, Equatable {
    var preset: PerformancePreset
    var foregroundPollingSeconds: Double
    var backgroundPollingSeconds: Double
    var keepOnTopEnforcementSeconds: Double
    var miniMapHoverTitlesEnabled: Bool
    var fastLiveRefreshEnabled: Bool
    var keepOnTopEnforcementEnabled: Bool

    static let balanced = PerformanceSettings(
        preset: .balanced,
        foregroundPollingSeconds: 1.5,
        backgroundPollingSeconds: 5.0,
        keepOnTopEnforcementSeconds: 2.5,
        miniMapHoverTitlesEnabled: true,
        fastLiveRefreshEnabled: false,
        keepOnTopEnforcementEnabled: true
    )

    static let responsive = PerformanceSettings(
        preset: .responsive,
        foregroundPollingSeconds: 0.8,
        backgroundPollingSeconds: 2.0,
        keepOnTopEnforcementSeconds: 0.8,
        miniMapHoverTitlesEnabled: true,
        fastLiveRefreshEnabled: true,
        keepOnTopEnforcementEnabled: true
    )

    static let passiveBaseline = PerformanceSettings(
        preset: .passiveBaseline,
        foregroundPollingSeconds: 2.0,
        backgroundPollingSeconds: 10.0,
        keepOnTopEnforcementSeconds: 2.5,
        miniMapHoverTitlesEnabled: false,
        fastLiveRefreshEnabled: false,
        keepOnTopEnforcementEnabled: true
    )

    static let lowCPU = PerformanceSettings(
        preset: .lowCPU,
        foregroundPollingSeconds: 3.0,
        backgroundPollingSeconds: 10.0,
        keepOnTopEnforcementSeconds: 3.0,
        miniMapHoverTitlesEnabled: false,
        fastLiveRefreshEnabled: false,
        keepOnTopEnforcementEnabled: false
    )

    static func defaults(for preset: PerformancePreset) -> PerformanceSettings {
        switch preset {
        case .balanced:
            return .balanced
        case .responsive:
            return .responsive
        case .passiveBaseline:
            return .passiveBaseline
        case .lowCPU:
            return .lowCPU
        case .custom:
            return .balanced
        }
    }

    func matchesPreset(_ preset: PerformancePreset) -> Bool {
        let base = Self.defaults(for: preset)
        return foregroundPollingSeconds == base.foregroundPollingSeconds &&
            backgroundPollingSeconds == base.backgroundPollingSeconds &&
            keepOnTopEnforcementSeconds == base.keepOnTopEnforcementSeconds &&
            miniMapHoverTitlesEnabled == base.miniMapHoverTitlesEnabled &&
            fastLiveRefreshEnabled == base.fastLiveRefreshEnabled &&
            keepOnTopEnforcementEnabled == base.keepOnTopEnforcementEnabled
    }

    var overlayRefreshPolicy: OverlayRefreshPolicy {
        switch preset {
        case .responsive:
            return .full
        case .balanced, .passiveBaseline, .lowCPU, .custom:
            return .reduced
        }
    }
}
