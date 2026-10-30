import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
// 메뉴바 전용 앱이라 Dock 에도 앱 전환기에도 나오지 않는다.
application.setActivationPolicy(.accessory)
application.run()
