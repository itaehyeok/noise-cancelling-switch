import Carbon.HIToolbox
import Foundation

/// 사용자가 지정한 전역 단축키 한 벌.
struct HotkeyCombo: Equatable {
    var keyCode: UInt32
    /// Carbon 수정자 워드 (cmdKey / shiftKey / optionKey / controlKey 의 OR).
    var carbonModifiers: UInt32

    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }
}

enum Preferences {
    private static let keyCodeKey = "hotkey.keyCode"
    private static let modifiersKey = "hotkey.carbonModifiers"
    private static let hasHotkeyKey = "hotkey.assigned"
    private static let firstRunKey = "app.hasCompletedFirstRun"
    private static let languageKey = "app.language"

    /// 표시 언어. 저장된 값이 없으면 영어로 시작한다.
    static var language: AppLanguage {
        get {
            guard let raw = defaults.string(forKey: languageKey),
                  let value = AppLanguage(rawValue: raw) else { return .english }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: languageKey) }
    }

    /// 첫 실행에는 자동 실행 설정과 무관하게 설정창을 띄워 위치를 알린다.
    static var hasCompletedFirstRun: Bool {
        get { defaults.bool(forKey: firstRunKey) }
        set { defaults.set(newValue, forKey: firstRunKey) }
    }

    private static var defaults: UserDefaults { .standard }

    /// 아직 한 번도 정하지 않았을 때 쓰는 단축키(⌃⌥Z). 왼손 하나로 누를 수 있고,
    /// 시스템 단축키·Xcode 메뉴·창 정리 앱(Magnet·Rectangle) 기본값과 겹치지 않는다.
    static let defaultHotkey = HotkeyCombo(keyCode: UInt32(kVK_ANSI_Z),
                                           carbonModifiers: UInt32(controlKey | optionKey))

    /// 한 번도 정한 적이 없으면 기본 단축키를 쓴다.
    /// 사용자가 설정창에서 지운 경우는 `hotkey.assigned = false` 로 남아 미할당이 유지된다.
    static var hotkey: HotkeyCombo? {
        get {
            guard defaults.object(forKey: hasHotkeyKey) != nil else { return defaultHotkey }
            guard defaults.bool(forKey: hasHotkeyKey) else { return nil }
            let code = UInt32(defaults.integer(forKey: keyCodeKey))
            let mods = UInt32(defaults.integer(forKey: modifiersKey))
            return HotkeyCombo(keyCode: code, carbonModifiers: mods)
        }
        set {
            if let c = newValue {
                defaults.set(true, forKey: hasHotkeyKey)
                defaults.set(Int(c.keyCode), forKey: keyCodeKey)
                defaults.set(Int(c.carbonModifiers), forKey: modifiersKey)
            } else {
                defaults.set(false, forKey: hasHotkeyKey)
                defaults.removeObject(forKey: keyCodeKey)
                defaults.removeObject(forKey: modifiersKey)
            }
        }
    }
}

/// 가상 키코드를 사람이 읽는 이름으로. 표시 전용이라 레이아웃 독립적인 이름만 쓴다.
enum KeyCodeNames {
    private static let table: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
        34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
        12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
        16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7",
        28: "8", 25: "9",
        27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
        43: ",", 47: ".", 44: "/", 50: "`",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
    ]

    /// 숫자 키패드 키. 이름에 언어별 꼬리표가 붙어 따로 둔다.
    private static let keypadTable: [UInt32: String] = [
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6",
        89: "7", 91: "8", 92: "9", 65: ".", 67: "*", 69: "+", 75: "/",
        78: "-", 76: "↩"
    ]

    static func name(for code: UInt32) -> String {
        if let name = table[code] { return name }
        if let key = keypadTable[code] {
            return L10n.t("\(key) (keypad)", "\(key)(키패드)")
        }
        return L10n.t("Key code \(code)", "키코드 \(code)")
    }

    /// 수정자 없이 단독으로 허용할 키인지. 기능키와 키패드 엔터 정도만 허용한다.
    static func allowsBareUse(_ code: UInt32) -> Bool {
        let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101,
                                         109, 103, 111, 105, 107, 113, 106, 64,
                                         79, 80, 90]
        return functionKeys.contains(code)
    }
}
