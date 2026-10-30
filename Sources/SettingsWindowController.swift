import AppKit

/// 설정창. 표시 언어, 자동 실행, 토글 단축키를 여기서 정한다.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let launchAtLoginNote = SettingsWindowController.makeNote("")
    private var recorder: HotkeyRecorderView!
    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private let hotkeyNote = SettingsWindowController.makeNote("")
    private let modeLabel = SettingsWindowController.makeValueLabel()
    private let helperLabel = SettingsWindowController.makeValueLabel()

    /// 라벨 열은 두 언어의 글자 길이가 달라서 가장 긴 것에 맞춰 폭을 정한다.
    private var labelCells: [NSTextField] = []
    private var labelWidthConstraints: [NSLayoutConstraint] = []

    private static var hotkeyHelpText: String {
        L10n.t("""
               Click the field, then press the combination you want. \
               esc cancels, delete clears it.
               It works even when the app is not in front. No Accessibility permission is needed.
               Registering can succeed and still not fire if another app or the system \
               claims the same combination. Try it, and pick another one if it does nothing.
               """,
               """
               칸을 클릭한 뒤 원하는 조합을 누르세요. esc 로 취소, delete 로 지웁니다.
               앱이 앞에 없어도 작동합니다. 접근성 권한은 필요하지 않습니다.
               등록에 성공해도 다른 앱이나 시스템이 같은 조합을 먼저 가져갈 수 있습니다. \
               눌러 보고 안 되면 다른 조합으로 바꾸세요.
               """)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    // MARK: 구성

    /// 화면 전체를 다시 만든다. 언어를 바꾸면 그대로 다시 부른다.
    private func buildContent() {
        guard let window else { return }
        window.title = L10n.t("\(AppInfo.name) Settings", "\(AppInfo.name) 설정")

        labelCells.removeAll()
        labelWidthConstraints.removeAll()

        let title = NSTextField(labelWithString: AppInfo.name)
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitle = Self.makeNote(L10n.t(
            "Click the menu bar icon to switch between Noise Cancellation and Transparency.",
            "메뉴바 아이콘을 클릭하면 노이즈 캔슬링과 주변음 허용을 오갑니다."))

        // 언어
        languagePopUp.removeAllItems()
        languagePopUp.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        if let index = AppLanguage.allCases.firstIndex(of: Preferences.language) {
            languagePopUp.selectItem(at: index)
        }
        languagePopUp.target = self
        languagePopUp.action = #selector(changeLanguage(_:))
        languagePopUp.translatesAutoresizingMaskIntoConstraints = false
        languagePopUp.widthAnchor.constraint(equalToConstant: 160).isActive = true

        let languageRow = row(L10n.t("Language", "언어"), languagePopUp)

        // 일반
        launchAtLoginCheckbox.title = L10n.t("Launch at login", "로그인할 때 자동으로 실행")
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin(_:))
        let launchRow = row("", launchAtLoginCheckbox)

        // 단축키
        recorder = HotkeyRecorderView(combo: Preferences.hotkey)
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 170).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        recorder.onChange = { [weak self] combo in
            guard let self else { return }
            let applied = HotkeyManager.shared.apply(combo)
            // 등록에 실패한 조합을 저장해 두면 다음 실행에도 조용히 실패한다.
            Preferences.hotkey = applied ? combo : nil
            if !applied { self.recorder.setCombo(nil) }
            self.clearButton.isEnabled = Preferences.hotkey != nil
            self.updateHotkeyNote(applied: applied)
        }
        // 녹화하는 동안에는 기존 단축키를 풀어야 같은 조합을 다시 지정할 수 있다.
        recorder.onRecordingStateChanged = { recording in
            if recording {
                HotkeyManager.shared.unregister()
            } else {
                HotkeyManager.shared.apply(Preferences.hotkey)
            }
        }

        clearButton.title = L10n.t("Clear", "지우기")
        clearButton.target = self
        clearButton.action = #selector(clearHotkey)
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.isEnabled = Preferences.hotkey != nil

        launchAtLoginNote.isHidden = launchAtLoginNote.stringValue.isEmpty

        hotkeyNote.stringValue = Self.hotkeyHelpText
        let hotkeyRow = row(L10n.t("Toggle shortcut", "토글 단축키"), recorder, clearButton)

        // 상태
        let modeRow = row(L10n.t("Current mode", "현재 모드"), modeLabel)
        let helperRow = row(L10n.t("Control engine", "제어 엔진"), helperLabel)

        let stack = NSStackView(views: [
            title,
            subtitle,
            sectionHeader(L10n.t("General", "일반")),
            languageRow,
            launchRow,
            launchAtLoginNote,
            sectionHeader(L10n.t("Shortcut", "단축키")),
            hotkeyRow,
            hotkeyNote,
            sectionHeader(L10n.t("Status", "상태")),
            modeRow,
            helperRow
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(16, after: launchAtLoginNote)
        stack.setCustomSpacing(16, after: hotkeyNote)
        stack.translatesAutoresizingMaskIntoConstraints = false

        applyLabelColumnWidth()

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22)
        ])
        window.contentView = content

        // 내용에 맞춰 창 높이를 잡는다. 고정 크기로 두면 문구가 길어졌을 때 잘린다.
        let fitting = content.fittingSize
        window.setContentSize(NSSize(width: 500, height: max(fitting.height + 22, 380)))
        window.contentMinSize = NSSize(width: 440, height: 360)
    }

    /// 왼쪽 라벨 한 칸과 오른쪽 내용들로 한 줄을 만든다.
    private func row(_ label: String, _ views: NSView...) -> NSStackView {
        let cell = labelCell(label)
        let stack = NSStackView(views: [cell] + views)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private func labelCell(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        labelCells.append(label)
        return label
    }

    /// 언어에 따라 라벨 길이가 달라지므로 가장 긴 것에 맞춰 한 폭으로 정렬한다.
    private func applyLabelColumnWidth() {
        for constraint in labelWidthConstraints { constraint.isActive = false }
        labelWidthConstraints.removeAll()
        let widest = labelCells.map(\.intrinsicContentSize.width).max() ?? 78
        let width = max(widest, 60)
        for cell in labelCells {
            let constraint = cell.widthAnchor.constraint(equalToConstant: width)
            constraint.isActive = true
            labelWidthConstraints.append(constraint)
        }
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func makeNote(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = 440
        return label
    }

    /// 상태 값 라벨은 헬퍼의 오류 원문이 들어올 수 있어 반드시 줄바꿈되어야 한다.
    private static func makeValueLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 12)
        label.isSelectable = true
        label.preferredMaxLayoutWidth = 330
        return label
    }

    // MARK: 동작

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0, index < AppLanguage.allCases.count else { return }
        let chosen = AppLanguage.allCases[index]
        guard chosen != Preferences.language else { return }

        recorder.cancelRecording()
        Preferences.language = chosen
        L10n.current = chosen
        // 메뉴바 툴팁과 메인 메뉴도 함께 바뀌어야 한다.
        NotificationCenter.default.post(name: L10n.didChangeNotification, object: nil)
        // 화면을 통째로 다시 만든다. 라벨 폭까지 새 언어에 맞춰 다시 잡힌다.
        buildContent()
        refresh()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        recorder.cancelRecording()
        let wanted = sender.state == .on
        let problem = LaunchAtLogin.set(wanted)
        // 요청 결과를 추정하지 않고 실제 상태를 다시 읽어 체크박스를 맞춘다.
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
        showLaunchNote(problem ?? LaunchAtLogin.statusNote, isError: problem != nil)
    }

    @objc private func clearHotkey() {
        recorder.cancelRecording()
        Preferences.hotkey = nil
        HotkeyManager.shared.apply(nil)
        recorder.setCombo(nil)
        clearButton.isEnabled = false
        updateHotkeyNote(applied: true)
    }

    private func showLaunchNote(_ text: String, isError: Bool) {
        launchAtLoginNote.stringValue = text
        launchAtLoginNote.textColor = isError ? .systemRed : .secondaryLabelColor
        // 빈 안내문도 한 줄 높이를 차지해 체크박스와 다음 구역 사이가 어색하게 벌어진다.
        // 스택뷰는 숨긴 뷰를 접어 주므로 내용이 없으면 숨긴다.
        launchAtLoginNote.isHidden = text.isEmpty
    }

    private func updateHotkeyNote(applied: Bool) {
        if applied {
            hotkeyNote.stringValue = Self.hotkeyHelpText
            hotkeyNote.textColor = .secondaryLabelColor
        } else {
            // 실패 원인을 단정하지 않는다. Carbon 은 타 앱 충돌로는 실패하지 않으므로
            // "다른 앱이 쓰고 있다" 는 설명은 사실이 아니다.
            hotkeyNote.stringValue = L10n.t(
                "Could not register this combination. Try a different one.",
                "이 조합을 등록하지 못했습니다. 다른 조합을 눌러 보세요.")
            hotkeyNote.textColor = .systemRed
        }
    }

    // MARK: 창 상태

    /// 녹화 중에 창을 닫거나 포커스를 잃으면 단축키가 풀린 채로 남는다. 반드시 되돌린다.
    func windowWillClose(_ notification: Notification) {
        recorder.cancelRecording()
    }

    func windowDidResignKey(_ notification: Notification) {
        recorder.cancelRecording()
    }

    /// 창을 띄울 때마다 현재 상태를 다시 읽어 반영한다.
    /// 어떤 경로로 꼬였든 여기서 무조건 복구되게 한다.
    func refresh() {
        recorder.cancelRecording()
        HotkeyManager.shared.apply(Preferences.hotkey)

        if let index = AppLanguage.allCases.firstIndex(of: Preferences.language) {
            languagePopUp.selectItem(at: index)
        }

        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        showLaunchNote(LaunchAtLogin.statusNote, isError: LaunchAtLogin.needsApproval)

        recorder.setCombo(Preferences.hotkey)
        clearButton.isEnabled = Preferences.hotkey != nil
        // 저장된 단축키가 있는데 등록이 안 됐다면 그 사실이 드러나야 한다.
        updateHotkeyNote(applied: Preferences.hotkey == nil || HotkeyManager.shared.currentCombo != nil)

        let checking = L10n.t("Checking...", "확인 중...")
        helperLabel.stringValue = checking
        helperLabel.textColor = .secondaryLabelColor
        AirPodsEngine.shared.diagnoseHelper { [weak self] diagnosis in
            guard let self else { return }
            self.helperLabel.stringValue = diagnosis.message
            self.helperLabel.textColor = diagnosis.isOK ? .secondaryLabelColor : .systemRed
        }

        modeLabel.stringValue = checking
        modeLabel.textColor = .secondaryLabelColor
        AirPodsEngine.shared.refresh { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .mode(let mode):
                self.modeLabel.stringValue = mode.displayName
                self.modeLabel.textColor = .labelColor
            case .noDevice:
                self.modeLabel.stringValue = L10n.t("AirPods are not connected",
                                                    "에어팟이 연결되어 있지 않습니다")
                self.modeLabel.textColor = .secondaryLabelColor
            case .helperMissing:
                self.modeLabel.stringValue = L10n.t("Control engine not found",
                                                    "제어 엔진을 찾을 수 없습니다")
                self.modeLabel.textColor = .systemRed
            case .failure(let reason):
                self.modeLabel.stringValue = reason
                self.modeLabel.textColor = .systemRed
            }
        }
    }

    func present() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
