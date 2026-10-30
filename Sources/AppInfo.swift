import Foundation

/// 앱 이름 같은 신원 정보를 한곳에 모은다.
///
/// 화면 문구 어디에서도 이름을 직접 적지 않는다.
/// 이름을 다시 바꿀 때 고칠 곳이 여기 한 군데면 된다.
enum AppInfo {
    /// 사용자에게 보이는 이름. Info.plist 의 CFBundleDisplayName 과 같아야 한다.
    static let name = "Noise Cancelling Switch"

    /// 콘솔 로그 접두사. 걸러 보기 좋게 짧게 둔다.
    static let logTag = "NCSwitch"
}
