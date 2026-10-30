import AppKit

/// 메뉴바 아이콘과 그 동작.
///
/// 왼쪽 클릭은 바로 토글하고, 오른쪽 클릭은 메뉴를 연다.
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var currentMode: ListeningMode?
    private var isBusy = false
    private var lastError: String?
    private var pollTimer: Timer?

    /// 진행 중인 작업 세대. 워치독이 엉뚱한 작업을 취소하지 않게 구분한다.
    private var operationGeneration = 0
    /// 바쁜 동안 들어온 토글 요청을 한 번만 기억했다가 끝나고 이어서 실행한다.
    private var hasPendingToggle = false

    /// 헬퍼 응답을 기다리지 않고 예상 모드를 먼저 표시한 상태인가.
    private var isShowingPredictedMode = false
    /// 헬퍼가 결과를 확정해 준 시각. 직후의 HAL 폴링이 낡은 값으로 되돌리는 것을 막는다.
    private var lastConfirmedAt: Date?

    /// 메뉴가 열려 있는 동안 비동기 갱신 결과를 반영하기 위해 들고 있는다.
    private weak var activeMenu: NSMenu?

    /// 설정창을 열어 달라는 요청.
    var onOpenSettings: (() -> Void)?

    override init() {
        super.init()
        configureButton()
        updateAppearance()
        startCheapPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    // MARK: 클릭 처리

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            toggle()
        }
    }

    /// 전역 단축키와 메뉴바 왼쪽 클릭이 함께 부른다.
    func toggle() {
        guard !isBusy else {
            // 연타를 버리면 노캔에서 주변음으로 갔다 돌아오는 조작이 한 번만 먹는다.
            // 한 번만 기억했다가 지금 작업이 끝나면 이어서 실행한다.
            hasPendingToggle = true
            return
        }
        // 헬퍼는 콜드 스타트에 700ms 넘게 걸린다. 그 시간을 기다렸다 아이콘을 바꾸면
        // 단축키를 눌러도 한참 반응이 없는 것처럼 느껴진다.
        // 토글 결과는 현재 모드로부터 결정되므로 먼저 바꿔 놓고 나중에 바로잡는다.
        beginOperation(predicting: currentMode.map(Self.nextMode))
        AirPodsEngine.shared.toggle { [weak self] outcome in
            self?.endOperation(with: outcome, userInitiated: true)
        }
    }

    /// 노캔과 주변음 허용만 오간다. 적응형이나 끔 상태에서는 노캔으로 복귀한다.
    private static func nextMode(after mode: ListeningMode) -> ListeningMode {
        mode == .noiseCancellation ? .transparency : .noiseCancellation
    }

    private func setMode(_ mode: ListeningMode) {
        guard !isBusy else { return }
        beginOperation(predicting: mode)
        AirPodsEngine.shared.setMode(mode) { [weak self] outcome in
            self?.endOperation(with: outcome, userInitiated: true)
        }
    }

    /// 헬퍼를 실제로 불러 현재 상태를 다시 읽는다. 사용자 조작이 아니라 조용히 처리한다.
    func refreshFromHelper() {
        AirPodsEngine.shared.refresh { [weak self] outcome in
            self?.apply(outcome, userInitiated: false)
        }
    }

    /// predicting 이 있으면 그 모드를 즉시 표시한다. 없으면 진행 중 표시만 한다.
    private func beginOperation(predicting predicted: ListeningMode?) {
        isBusy = true
        operationGeneration += 1
        let generation = operationGeneration

        if let predicted {
            currentMode = predicted
            lastError = nil
            isShowingPredictedMode = true
        } else {
            isShowingPredictedMode = false
        }
        updateAppearance()
        updateOpenMenu()

        // completion 이 영영 오지 않아도 앱이 잠기지 않게 한다.
        // 엔진에도 시한이 있지만, 이중으로 막아야 아이콘이 영구히 굳는 일이 없다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.isBusy, self.operationGeneration == generation else { return }
            self.isBusy = false
            // 예상해서 보여준 모드가 실제로 적용됐는지 알 수 없으므로 미확정으로 되돌린다.
            self.isShowingPredictedMode = false
            self.currentMode = nil
            self.lastError = L10n.t("No response, so the operation was cancelled",
                                    "응답이 없어 작업을 중단했습니다")
            self.updateAppearance()
            self.updateOpenMenu()
        }
    }

    private func endOperation(with outcome: EngineOutcome, userInitiated: Bool) {
        isBusy = false
        operationGeneration += 1
        apply(outcome, userInitiated: userInitiated)

        if hasPendingToggle {
            hasPendingToggle = false
            // 방금 끝난 작업이 실패했다면 이어서 또 시도할 이유가 없다.
            if case .mode = outcome { toggle() }
        }
    }

    private func apply(_ outcome: EngineOutcome, userInitiated: Bool) {
        isShowingPredictedMode = false
        switch outcome {
        case .mode(let mode):
            currentMode = mode
            lastError = nil
            lastConfirmedAt = Date()
        case .noDevice:
            currentMode = nil
            lastError = nil
            // 단축키로 눌렀다면 화면에 아무 변화가 없어 실패를 알 방법이 없다.
            if userInitiated { NSSound.beep() }
        case .helperMissing:
            currentMode = nil
            lastError = L10n.t("Control engine not found", "제어 엔진을 찾을 수 없습니다")
            if userInitiated { NSSound.beep() }
        case .failure(let reason):
            // 실패하면 현재 모드를 확정할 수 없다. 낡은 값을 계속 보여주면 안 된다.
            currentMode = nil
            lastError = reason
            if userInitiated { NSSound.beep() }
        }
        updateAppearance()
        updateOpenMenu()
    }

    // MARK: 가벼운 상태 감시

    /// HAL 읽기는 프로세스를 띄우지 않아 사실상 공짜다. 그래서 짧은 주기로 돌려도 된다.
    /// HAL 이 없는 환경이면 아무 일도 하지 않고, 상태는 이벤트가 있을 때만 갱신된다.
    private func startCheapPolling() {
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, !self.isBusy else { return }
            AirPodsEngine.shared.readModeViaHAL { [weak self] mode in
                guard let self, let mode, !self.isBusy else { return }
                guard mode != self.currentMode else { return }
                // 헬퍼가 방금 확정해 준 값이 HAL 에 아직 반영되지 않았을 수 있다.
                // 그 사이에 폴링이 끼어들면 아이콘이 한 번 되돌아갔다 다시 바뀐다.
                if let confirmed = self.lastConfirmedAt, Date().timeIntervalSince(confirmed) < 2.0 {
                    return
                }
                self.currentMode = mode
                self.lastError = nil
                self.updateAppearance()
                self.updateOpenMenu()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// 표시 언어가 바뀌었을 때 호출한다. 메뉴는 열 때마다 새로 만들므로 툴팁만 갱신하면 된다.
    func languageDidChange() {
        updateAppearance()
    }

    /// 오디오 기기 구성이 바뀌었을 때 호출한다.
    func audioDevicesChanged() {
        guard !isBusy else { return }
        AirPodsEngine.shared.readModeViaHAL { [weak self] mode in
            guard let self, !self.isBusy else { return }
            if let mode {
                self.currentMode = mode
                self.lastError = nil
                self.updateAppearance()
                self.updateOpenMenu()
            } else {
                // HAL 로 못 읽으면 기기가 빠졌을 수도, HAL 이 없는 환경일 수도 있다.
                // 헬퍼에게 물어 확정한다. 엔진이 중복 요청을 걸러 준다.
                self.refreshFromHelper()
            }
        }
    }

    // MARK: 모양

    private func updateAppearance() {
        guard let button = statusItem.button else { return }

        let candidates = currentMode?.symbolCandidates ?? ["airpodspro", "ear"]
        button.image = Self.symbolImage(candidates)
        // 흐린 표시는 "쓸 수 없는 상태" 전용이다. 작업 중은 투명도로 따로 알린다.
        // 둘을 같은 표시로 쓰면 토글할 때마다 연결이 끊긴 것처럼 보인다.
        button.appearsDisabled = currentMode == nil
        // 예상 모드를 이미 보여주고 있으면 흐리게 만들지 않는다.
        // 그래야 단축키를 누른 즉시 바뀐 것처럼 보인다.
        button.alphaValue = (isBusy && !isShowingPredictedMode) ? 0.45 : 1.0
        button.toolTip = tooltipText
    }

    private var tooltipText: String {
        var lines = [AppInfo.name]
        if let mode = currentMode {
            lines.append(L10n.t("Current mode: \(mode.displayName)", "현재 모드: \(mode.displayName)"))
        } else {
            lines.append(L10n.t("AirPods are not connected", "에어팟이 연결되어 있지 않습니다"))
        }
        // 저장값이 아니라 실제 등록 상태를 보여야 한다.
        // 등록에 실패했는데 단축키가 있다고 알리면 사용자가 원인을 못 찾는다.
        if let saved = Preferences.hotkey {
            if HotkeyManager.shared.currentCombo != nil {
                lines.append(L10n.t("Shortcut: \(saved.displayString)", "단축키: \(saved.displayString)"))
            } else {
                lines.append(L10n.t("Shortcut: \(saved.displayString) (not registered)",
                                    "단축키: \(saved.displayString) (등록 실패)"))
            }
        }
        if let lastError {
            lines.append(L10n.t("Error: \(lastError)", "오류: \(lastError)"))
        }
        return lines.joined(separator: "\n")
    }

    /// 후보 심볼 중 이 macOS 에 존재하는 첫 번째를 쓴다.
    private static func symbolImage(_ names: [String]) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        for name in names {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: AppInfo.name) {
                image.isTemplate = true
                return image.withSymbolConfiguration(config) ?? image
            }
        }
        return nil
    }

    // MARK: 메뉴

    private static let headerItemTag = 100
    private static let modeItemTagBase = 200
    private static let selectableModes: [ListeningMode] = [.noiseCancellation, .transparency]

    private func showMenu() {
        let menu = NSMenu()
        menu.delegate = self
        // 자동 활성화를 끄지 않으면 아래에서 지정한 isEnabled 가 표시 직전에 덮어써진다.
        // 그러면 에어팟이 없을 때도 모드 항목이 눌리는 것처럼 보인다.
        menu.autoenablesItems = false

        let headerItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.tag = Self.headerItemTag
        menu.addItem(headerItem)
        menu.addItem(.separator())

        for (index, mode) in Self.selectableModes.enumerated() {
            let item = NSMenuItem(title: mode.displayName,
                                  action: #selector(selectMode(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.tag = Self.modeItemTagBase + index
            item.state = currentMode == mode ? .on : .off
            item.isEnabled = currentMode != nil && !isBusy
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.t("Settings...", "설정..."),
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: L10n.t("Quit \(AppInfo.name)", "\(AppInfo.name) 종료"),
                                  action: #selector(quit),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        activeMenu = menu

        // 상태 아이템에 메뉴를 잠깐 붙였다가 떼는 것이 좌우 클릭을 함께 쓰는 표준적인 방법이다.
        // performClick 은 메뉴가 닫힐 때까지 돌아오지 않는다.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        activeMenu = nil
    }

    /// 오류가 있으면 그것부터 보여준다. 툴팁 말고는 오류를 알릴 곳이 없기 때문이다.
    private var headerTitle: String {
        if let lastError { return lastError }
        if let mode = currentMode {
            return L10n.t("Current mode: \(mode.displayName)", "현재 모드: \(mode.displayName)")
        }
        return L10n.t("AirPods are not connected", "에어팟이 연결되어 있지 않습니다")
    }

    /// 메뉴가 열려 있는 동안 상태가 바뀌면 항목을 갱신한다.
    /// 갱신이 비동기라 메뉴를 만든 뒤에 결과가 오는 일이 흔하다.
    private func updateOpenMenu() {
        guard let menu = activeMenu else { return }
        menu.item(withTag: Self.headerItemTag)?.title = headerTitle
        for (index, mode) in Self.selectableModes.enumerated() {
            guard let item = menu.item(withTag: Self.modeItemTagBase + index) else { continue }
            item.state = currentMode == mode ? .on : .off
            item.isEnabled = currentMode != nil && !isBusy
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshFromHelper()
    }

    func menuDidClose(_ menu: NSMenu) {
        activeMenu = nil
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = ListeningMode(rawValue: raw) else { return }
        setMode(mode)
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
