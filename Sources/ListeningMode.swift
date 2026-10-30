import Foundation

/// airpods-control 이 쓰는 모드 토큰과 1:1 대응한다.
enum ListeningMode: String, CaseIterable {
    case off
    case transparency
    case adaptive
    case noiseCancellation = "noise-cancellation"

    /// CLI 평문 출력 한 줄을 모드로 변환한다. 별칭도 받는다.
    init?(token raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch t {
        case "off": self = .off
        case "transparency", "trans": self = .transparency
        case "adaptive", "automatic", "auto": self = .adaptive
        case "noise-cancellation", "anc", "nc": self = .noiseCancellation
        default: return nil
        }
    }

    /// CoreAudio HAL 의 lstm 원시값. 1=Off 2=노캔 3=투명 4=적응형.
    init?(halRawValue v: UInt32) {
        switch v {
        case 1: self = .off
        case 2: self = .noiseCancellation
        case 3: self = .transparency
        case 4: self = .adaptive
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .off: return L10n.t("Off", "끔")
        case .transparency: return L10n.t("Transparency", "주변음 허용")
        case .adaptive: return L10n.t("Adaptive", "적응형")
        case .noiseCancellation: return L10n.t("Noise Cancellation", "노이즈 캔슬링")
        }
    }

    /// 메뉴바 아이콘으로 쓸 SF Symbol 이름 후보. 앞에서부터 존재하는 것을 쓴다.
    var symbolCandidates: [String] {
        switch self {
        case .noiseCancellation:
            return ["waveform.slash", "speaker.slash.fill", "ear.fill"]
        case .transparency:
            return ["waveform", "speaker.wave.2.fill", "ear"]
        case .adaptive:
            return ["waveform.badge.magnifyingglass", "waveform", "ear"]
        case .off:
            return ["waveform.badge.xmark", "speaker.fill", "ear"]
        }
    }
}
