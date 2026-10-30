import Foundation

/// 앱이 지원하는 표시 언어.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case korean = "ko"

    /// 선택 목록에는 각 언어를 그 언어 자체로 적는다.
    /// 지금 어떤 언어가 켜져 있든 자기 언어를 알아볼 수 있어야 하기 때문이다.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .korean: return "한국어"
        }
    }
}

/// 표시 문자열을 고르는 아주 작은 도우미.
///
/// .lproj 번들 대신 호출 지점에 두 언어를 나란히 적는 방식을 쓴다.
/// 문자열이 백여 개뿐이라 키 테이블을 따로 두면 누락과 오타만 늘고,
/// 이 방식은 앱을 다시 켜지 않고도 언어를 바꿀 수 있다.
enum L10n {
    /// 현재 언어. 앱 시작 때 저장된 값으로 맞추고, 설정에서 바꿀 때 갱신한다.
    static var current: AppLanguage = .english

    /// 영어 문자열과 한국어 문자열을 받아 현재 언어에 맞는 쪽을 돌려준다.
    static func t(_ english: String, _ korean: String) -> String {
        current == .english ? english : korean
    }

    /// 언어가 바뀌었을 때 화면을 다시 그리라고 알린다.
    static let didChangeNotification = Notification.Name("dev.itaehyeok.nocan.languageDidChange")
}
