import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBar: MenuBarController!
    private var settings: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 다른 무엇보다 먼저 언어를 정해야 이후에 만드는 문자열이 전부 맞는 언어로 나온다.
        L10n.current = Preferences.language
        installMainMenu()

        NotificationCenter.default.addObserver(
            self, selector: #selector(languageDidChange),
            name: L10n.didChangeNotification, object: nil)

        menuBar = MenuBarController()
        menuBar.onOpenSettings = { [weak self] in self?.showSettings() }

        HotkeyManager.shared.onPressed = { [weak self] in
            self?.menuBar.toggle()
        }
        if !HotkeyManager.shared.apply(Preferences.hotkey), Preferences.hotkey != nil {
            NSLog("\(AppInfo.logTag): could not register the saved shortcut")
        }

        AirPodsEngine.shared.onAudioDevicesChanged = { [weak self] in
            self?.menuBar.audioDevicesChanged()
        }
        AirPodsEngine.shared.startObservingAudioDevices()

        menuBar.refreshFromHelper()

        if shouldShowSettingsOnLaunch {
            showSettings()
        }
    }

    /// 앱이 이미 돌고 있을 때 다시 실행하면 설정창을 연다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        if settings == nil {
            settings = SettingsWindowController()
        }
        settings?.present()
    }

    // MARK: 언어

    @objc private func languageDidChange() {
        installMainMenu()
        menuBar.languageDidChange()
    }

    /// nib 없는 앱에는 AppKit 이 기본 메뉴를 만들어 주지 않는다.
    /// 메뉴 막대에 보이지는 않지만, 이게 없으면 설정창에서 ⌘W 와 ⌘Q 가 아예 동작하지 않는다.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("Quit \(AppInfo.name)", "\(AppInfo.name) 종료"),
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.t("Window", "윈도우"))
        windowMenu.addItem(withTitle: L10n.t("Close", "닫기"),
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// 실행하자마자 설정창을 띄울지 정한다.
    ///
    /// 로그인 실행과 수동 실행을 구별하는 믿을 만한 방법이 없다.
    /// XPC_SERVICE_NAME 은 open 으로 띄워도 채워지고,
    /// NSApplicationLaunchIsDefaultLaunchKey 도 헤더가 나열하는 false 조건에
    /// 로그인 항목이 없어 실측상 둘 다 1 로 온다.
    ///
    /// 그래서 판정 대신 규칙으로 정한다. 자동 실행을 켜 둔 사용자는 매 로그인마다
    /// 창이 튀어나오면 안 되므로 띄우지 않는다. 그 경우에도 앱을 다시 실행하면
    /// applicationShouldHandleReopen 으로 창이 열리고, 메뉴바 우클릭에도 설정이 있다.
    /// 첫 실행만은 자동 실행 여부와 무관하게 띄워 설정 위치를 알린다.
    private var shouldShowSettingsOnLaunch: Bool {
        if !Preferences.hasCompletedFirstRun {
            Preferences.hasCompletedFirstRun = true
            return true
        }
        return !LaunchAtLogin.isEnabled
    }
}
