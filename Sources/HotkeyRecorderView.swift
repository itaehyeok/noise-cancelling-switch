import AppKit
import Carbon.HIToolbox

/// 단축키를 눌러서 지정하는 입력 칸.
///
/// 클릭하면 녹화가 시작되고, 다음에 누르는 조합을 그대로 받는다.
/// esc 는 취소, delete 는 지우기다.
final class HotkeyRecorderView: NSView {

    /// 조합이 바뀔 때마다 불린다. nil 은 할당 해제다.
    var onChange: ((HotkeyCombo?) -> Void)?
    /// 녹화가 시작되고 끝날 때 불린다. 녹화 중에는 기존 전역 단축키를 잠시 풀어야 한다.
    var onRecordingStateChanged: ((Bool) -> Void)?

    private(set) var combo: HotkeyCombo? {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet {
            needsDisplay = true
            onRecordingStateChanged?(isRecording)
        }
    }

    /// 녹화 중 사용자가 지금 누르고 있는 수정자. 미리보기로만 쓴다.
    private var liveModifiers: NSEvent.ModifierFlags = []

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 26) }
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(combo: HotkeyCombo?) {
        self.combo = combo
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("사용하지 않음") }

    func setCombo(_ newValue: HotkeyCombo?) {
        combo = newValue
    }

    /// 녹화 중이면 취소한다. didSet 이 onRecordingStateChanged(false) 를 불러
    /// 기존 단축키가 다시 등록된다. 창을 닫거나 포커스를 잃을 때 반드시 불러야 한다.
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        liveModifiers = []
    }

    // MARK: 마우스

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording.toggle()
        liveModifiers = []
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            isRecording = false
            liveModifiers = []
        }
        return super.resignFirstResponder()
    }

    // MARK: 키 입력

    /// 수정자가 붙은 조합은 keyDown 보다 먼저 이쪽으로 온다. 녹화 중에는 여기서 가로챈다.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        _ = handle(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        liveModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        needsDisplay = true
    }

    private func handle(_ event: NSEvent) -> Bool {
        let keyCode = UInt32(event.keyCode)
        let carbon = Self.carbonModifiers(from: event.modifierFlags)

        // 수정자 없이 누른 esc 는 취소, delete 는 지우기.
        // 수정자가 붙어 있으면 사용자가 그 조합을 단축키로 쓰려는 것이므로 건드리지 않는다.
        if carbon == 0 && keyCode == UInt32(kVK_Escape) {
            cancelRecording()
            return true
        }
        if carbon == 0 && (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) {
            combo = nil
            isRecording = false
            liveModifiers = []
            onChange?(nil)
            return true
        }

        let hasRealModifier = carbon & UInt32(cmdKey | optionKey | controlKey) != 0

        // 수정자 없는 조합은 기능키만 허용한다. 그냥 글자를 단축키로 잡으면 타이핑이 막힌다.
        guard hasRealModifier || KeyCodeNames.allowsBareUse(keyCode) else {
            NSSound.beep()
            return true
        }

        let newCombo = HotkeyCombo(keyCode: keyCode, carbonModifiers: carbon)
        combo = newCombo
        isRecording = false
        liveModifiers = []
        onChange?(newCombo)
        return true
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)

        let fill: NSColor
        if isRecording {
            fill = NSColor.controlAccentColor.withAlphaComponent(0.16)
        } else if isHovered {
            fill = NSColor.controlColor.blended(withFraction: 0.25, of: .controlTextColor) ?? .controlColor
        } else {
            fill = .controlColor
        }
        fill.setFill()
        path.fill()

        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            let preview = Self.modifierSymbols(liveModifiers)
            text = preview.isEmpty ? L10n.t("Press keys", "조합을 누르세요") : preview
            color = .controlAccentColor
        } else if let combo {
            text = combo.displayString
            color = .controlTextColor
        } else {
            text = L10n.t("Not set", "지정되지 않음")
            color = .tertiaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .medium : .regular),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    private static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s
    }
}
