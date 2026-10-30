import Foundation
import ServiceManagement

/// 로그인 항목 등록. macOS 13 부터의 SMAppService 를 쓴다.
///
/// 상태가 네 가지(notRegistered / enabled / requiresApproval / notFound)라
/// 켬과 끔이라는 두 값으로 접으면 사용자에게 거짓말을 하게 된다.
/// 그래서 모든 조작 뒤에 상태를 다시 읽어 실제 결과를 보고한다.
enum LaunchAtLogin {

    /// SMErrors.h 의 값. 헤더에서 직접 확인했다.
    private enum SMErrorCode {
        static let invalidSignature = 3
        static let jobNotFound = 6
        static let launchDeniedByUser = 11
        static let alreadyRegistered = 12
    }

    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// 로그 출력용 상태 문자열.
    static var statusDescriptionForLog: String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        @unknown default: return "unknown"
        }
    }

    static var isEnabled: Bool { status == .enabled }

    /// 사용자 승인이 필요해 앱 안에서는 켤 수 없는 상태인가.
    static var needsApproval: Bool { status == .requiresApproval }

    /// 실패하거나 요청과 다른 상태로 끝나면 사용자에게 보여줄 사유를 돌려준다.
    /// 요청대로 됐으면 nil.
    static func set(_ enabled: Bool) -> String? {
        let before = status

        if enabled && before == .requiresApproval {
            // 사용자가 시스템 설정에서 꺼둔 상태다. 앱이 되돌릴 수 없으니 그쪽을 열어 준다.
            SMAppService.openSystemSettingsLoginItems()
            return L10n.t("Turn \(AppInfo.name) on in System Settings > General > Login Items.",
                          "시스템 설정 > 일반 > 로그인 항목에서 \(AppInfo.name) 을 켜 주세요.")
        }

        do {
            if enabled {
                if before != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if before != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
        } catch let error as NSError {
            // 이미 없는 것을 지우는 것은 실패가 아니다.
            if !enabled && error.code == SMErrorCode.jobNotFound {
                return nil
            }
            return describe(error)
        }

        // 예외가 안 났어도 실제로 원하는 상태가 됐는지 확인한다.
        let after = status
        let wanted: SMAppService.Status = enabled ? .enabled : .notRegistered
        return after == wanted ? nil : describe(status: after, wantedEnabled: enabled)
    }

    private static func describe(_ error: NSError) -> String {
        switch error.code {
        case SMErrorCode.launchDeniedByUser:
            SMAppService.openSystemSettingsLoginItems()
            return L10n.t("Turn \(AppInfo.name) on in System Settings > General > Login Items.",
                          "시스템 설정 > 일반 > 로그인 항목에서 \(AppInfo.name) 을 켜 주세요.")
        case SMErrorCode.alreadyRegistered:
            return L10n.t("Already registered. Check System Settings > General > Login Items.",
                          "이미 등록되어 있습니다. 시스템 설정 > 일반 > 로그인 항목을 확인해 주세요.")
        case SMErrorCode.invalidSignature:
            return L10n.t("Registration failed because of the app signature. Rebuild and try again.",
                          "앱 서명 문제로 등록하지 못했습니다. 다시 빌드한 뒤 시도해 주세요.")
        case SMErrorCode.jobNotFound:
            return L10n.t("Registration info was not found. Move the app to the Applications folder and try again.", "등록 정보를 찾지 못했습니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요.")
        default:
            return L10n.t("Registration failed (code \(error.code)). \(error.localizedDescription)",
                          "등록에 실패했습니다 (코드 \(error.code)). \(error.localizedDescription)")
        }
    }

    private static func describe(status: SMAppService.Status, wantedEnabled: Bool) -> String {
        switch status {
        case .requiresApproval:
            return L10n.t("Turn \(AppInfo.name) on in System Settings > General > Login Items.",
                          "시스템 설정 > 일반 > 로그인 항목에서 \(AppInfo.name) 을 켜 주세요.")
        case .notFound:
            return L10n.t("Registration info was not found. Move the app to the Applications folder and try again.", "등록 정보를 찾지 못했습니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요.")
        case .enabled where !wantedEnabled:
            return L10n.t("Could not turn it off. Turn it off in System Settings > General > Login Items.",
                          "해제하지 못했습니다. 시스템 설정 > 일반 > 로그인 항목에서 꺼 주세요.")
        case .notRegistered where wantedEnabled:
            return L10n.t("It was not registered. Move the app to the Applications folder and try again.",
                          "등록되지 않았습니다. 앱을 응용 프로그램 폴더로 옮긴 뒤 다시 시도해 주세요.")
        default:
            return ""
        }
    }

    /// 체크박스만으로는 드러나지 않는 상태를 사용자에게 알릴 때 쓴다.
    static var statusNote: String {
        switch status {
        case .enabled, .notRegistered:
            return ""
        case .requiresApproval:
            return L10n.t("\(AppInfo.name) is turned off in System Settings > General > Login Items.",
                          "시스템 설정 > 일반 > 로그인 항목에서 \(AppInfo.name) 이 꺼져 있습니다.")
        case .notFound:
            return L10n.t("Registration info was not found. If you moved or rebuilt the app, turn this on again.",
                          "등록 정보를 찾을 수 없습니다. 앱을 옮겼거나 다시 빌드했다면 다시 켜 주세요.")
        @unknown default:
            return ""
        }
    }
}
