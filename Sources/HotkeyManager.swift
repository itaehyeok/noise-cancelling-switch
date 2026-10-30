import AppKit
import Carbon.HIToolbox

/// Carbon 의 RegisterEventHotKey 로 전역 단축키를 잡는다.
///
/// 이 경로를 쓰는 이유는 접근성 권한이 필요 없기 때문이다.
/// NSEvent 전역 모니터나 CGEventTap 은 권한을 요구하고 기능키의 fn 플래그 처리도 까다롭다.
final class HotkeyManager {
    static let shared = HotkeyManager()

    /// 단축키가 눌렸을 때 메인 큐에서 불린다.
    var onPressed: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registeredCombo: HotkeyCombo?

    private let signature: OSType = 0x4E4F4341  // 'NOCA'

    private init() {}

    var currentCombo: HotkeyCombo? { registeredCombo }

    /// 저장된 설정을 실제 등록 상태에 반영한다. nil 이면 아무것도 등록하지 않는다.
    @discardableResult
    func apply(_ combo: HotkeyCombo?) -> Bool {
        unregister()
        guard let combo else { return true }
        return register(combo)
    }

    @discardableResult
    private func register(_ combo: HotkeyCombo) -> Bool {
        guard installHandlerIfNeeded() else {
            NSLog("\(AppInfo.logTag): event handler install failed, cannot register a shortcut")
            return false
        }

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode,
                                         combo.carbonModifiers,
                                         id,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &ref)
        guard status == noErr, let ref else {
            NSLog("\(AppInfo.logTag): RegisterEventHotKey failed, status=\(status)")
            return false
        }
        hotKeyRef = ref
        registeredCombo = combo
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        hotKeyRef = nil
        registeredCombo = nil
    }

    /// 핸들러 설치에 성공했거나 이미 설치돼 있으면 true.
    private func installHandlerIfNeeded() -> Bool {
        guard handlerRef == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            guard hotKeyID.signature == manager.signature else { return noErr }
            DispatchQueue.main.async { manager.onPressed?() }
            return noErr
        }
        let status = InstallEventHandler(GetEventDispatcherTarget(),
                                         callback,
                                         1,
                                         &spec,
                                         Unmanaged.passUnretained(self).toOpaque(),
                                         &handlerRef)
        if status != noErr {
            NSLog("\(AppInfo.logTag): InstallEventHandler failed, status=\(status)")
            handlerRef = nil
            return false
        }
        return true
    }
}
