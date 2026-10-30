import CoreAudio
import Foundation

/// 엔진 호출 한 번의 결과.
enum EngineOutcome {
    /// 모드를 확정했다. 토글 결과이거나 현재 상태다.
    case mode(ListeningMode)
    /// 지원 기기가 붙어 있지 않다.
    case noDevice
    /// 헬퍼 실행 파일이 앱 번들 안에 없다.
    case helperMissing
    /// 그 밖의 실패. 사용자에게 보여줄 한 줄 사유.
    case failure(String)
}

/// 헬퍼 번들 상태 진단 결과.
enum HelperDiagnosis {
    case ok
    case problem(String)

    var isOK: Bool { if case .ok = self { return true }; return false }
    var message: String {
        switch self {
        case .ok: return L10n.t("OK", "정상")
        case .problem(let reason): return reason
        }
    }
}

/// airpods-control 헬퍼를 감싸고, 가능하면 CoreAudio HAL 로 상태를 싸게 읽는다.
///
/// 쓰기는 항상 헬퍼를 거친다. 헬퍼가 비공개 AVFoundation 경로와 HAL 경로를
/// 알아서 고르기 때문에 이 앱이 그 판단을 흉내 낼 이유가 없다.
final class AirPodsEngine {
    static let shared = AirPodsEngine()

    /// 헬퍼 실행 전용 직렬 큐. 헬퍼 호출을 순서대로 하나씩만 돌린다.
    private let helperQueue = DispatchQueue(label: "dev.itaehyeok.nocan.helper", qos: .userInitiated)
    /// HAL 읽기 전용 큐. 헬퍼가 오래 걸려도 상태 폴링이 막히지 않게 분리한다.
    private let halQueue = DispatchQueue(label: "dev.itaehyeok.nocan.hal", qos: .utility)

    /// 헬퍼가 응답하지 않을 때 포기하는 시한.
    private let helperTimeout: DispatchTimeInterval = .seconds(8)

    private var deviceListenerInstalled = false
    private var pendingDeviceChange: DispatchWorkItem?
    /// 헬퍼로 상태를 읽는 요청이 이미 떠 있는지. 중복 실행을 막는다.
    private var refreshInFlight = false
    /// 진행 중인 요청을 기다리는 completion 들. 버리면 호출자가 영영 응답을 못 받는다.
    private var refreshWaiters: [(EngineOutcome) -> Void] = []

    /// CoreAudio 기기 구성이 바뀌었을 때 불린다. 메인 큐에서 호출된다.
    var onAudioDevicesChanged: (() -> Void)?

    // MARK: 헬퍼 위치

    /// 헬퍼는 avbypass.dylib 와 같은 디렉터리에 있어야 한다.
    /// 헬퍼가 자기 실행 경로 옆에서 dylib 을 찾아 DYLD_INSERT_LIBRARIES 로 재실행하기 때문이다.
    var helperURL: URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let exe = res.appendingPathComponent("airpods-control")
        return FileManager.default.isExecutableFile(atPath: exe.path) ? exe : nil
    }

    /// 헬퍼가 실제로 동작하는지 진단한다.
    ///
    /// 파일 존재만 보면 부족하다. 이 구조에서 가장 깨지기 쉬운 곳은 dylib 주입이고,
    /// 그건 헬퍼를 실제로 돌려 stderr 를 봐야만 알 수 있다.
    func diagnoseHelper(completion: @escaping (HelperDiagnosis) -> Void) {
        guard let res = Bundle.main.resourceURL else {
            completion(.problem(L10n.t("Bundle resource path not found",
                                       "번들 리소스 경로를 찾을 수 없습니다")))
            return
        }
        let exe = res.appendingPathComponent("airpods-control")
        let dylib = res.appendingPathComponent("avbypass.dylib")
        let fm = FileManager.default
        if !fm.fileExists(atPath: exe.path) {
            completion(.problem(L10n.t("airpods-control is missing from the bundle",
                                       "airpods-control 이 번들에 없습니다")))
            return
        }
        if !fm.isExecutableFile(atPath: exe.path) {
            completion(.problem(L10n.t("airpods-control is not executable",
                                       "airpods-control 에 실행 권한이 없습니다")))
            return
        }
        if !fm.fileExists(atPath: dylib.path) {
            completion(.problem(L10n.t("avbypass.dylib is missing from the bundle",
                                       "avbypass.dylib 이 번들에 없습니다")))
            return
        }

        helperQueue.async {
            // status 는 쓰지 않는다. airpods-control v0.4.0 의 status 는 입력 전용
            // 블루투스 엔드포인트를 훑다가 SIGABRT 로 죽는다(이 기계에서 재현 확인).
            // listening-mode get 은 멀쩡하고, 진단에 필요한 bypass 로그도 똑같이 찍는다.
            let result = self.execute(["listening-mode", "get", "--debug"])
            let diagnosis: HelperDiagnosis
            switch result {
            case .timedOut:
                diagnosis = .problem(L10n.t("The helper is not responding",
                                            "헬퍼가 응답하지 않습니다"))
            case .launchFailed(let reason):
                diagnosis = .problem(L10n.t("Could not run the helper: \(reason)",
                                            "헬퍼를 실행하지 못했습니다: \(reason)"))
            case .finished(_, _, let stderr, let signalled):
                if stderr.contains("bypass.status=\"active\"") {
                    // 주입이 확인되면 그것으로 충분하다.
                    // 기기가 없어 exit 1 로 끝나는 것은 진단 실패가 아니다.
                    diagnosis = .ok
                } else if signalled {
                    diagnosis = .problem(L10n.t("The helper crashed. Try rebuilding",
                                                "헬퍼가 비정상 종료했습니다. 다시 빌드해 보세요"))
                } else if stderr.contains("dylib-missing") {
                    diagnosis = .problem(L10n.t("avbypass.dylib was not found",
                                                "avbypass.dylib 을 찾지 못했습니다"))
                } else {
                    diagnosis = .problem(L10n.t("dylib injection could not be confirmed. Try rebuilding",
                                                "dylib 주입이 확인되지 않았습니다. 다시 빌드해 보세요"))
                }
            }
            DispatchQueue.main.async { completion(diagnosis) }
        }
    }

    // MARK: 공개 동작

    /// 노캔과 주변음 허용 사이를 오간다. 적응형과 끔 상태에서는 둘 중 하나로 복귀한다.
    func toggle(completion: @escaping (EngineOutcome) -> Void) {
        run(["listening-mode", "cycle", "--modes", "noise-cancellation,transparency"],
            completion: completion)
    }

    /// 특정 모드로 직접 설정한다.
    func setMode(_ mode: ListeningMode, completion: @escaping (EngineOutcome) -> Void) {
        run(["listening-mode", "set", mode.rawValue], expecting: mode, completion: completion)
    }

    /// HAL 만으로 현재 모드를 읽는다. 프로세스를 띄우지 않지만 CoreAudio 호출이라
    /// 메인 스레드에서 부르면 안 된다. 헬퍼 큐와 분리돼 있어 헬퍼가 막혀도 동작한다.
    func readModeViaHAL(completion: @escaping (ListeningMode?) -> Void) {
        halQueue.async {
            let mode = HALListeningMode.read()
            DispatchQueue.main.async { completion(mode) }
        }
    }

    /// 현재 모드를 읽는다. HAL 로 먼저 시도하고, 안 되면 헬퍼를 부른다.
    /// 이미 같은 요청이 떠 있으면 중복 실행하지 않는다.
    func refresh(completion: @escaping (EngineOutcome) -> Void) {
        halQueue.async {
            if let halMode = HALListeningMode.read() {
                DispatchQueue.main.async { completion(.mode(halMode)) }
                return
            }
            DispatchQueue.main.async {
                // 이미 같은 요청이 떠 있으면 프로세스를 또 띄우지 않는다.
                // 다만 completion 은 버리지 않고 줄을 세웠다가 같은 결과로 함께 응답한다.
                if self.refreshInFlight {
                    self.refreshWaiters.append(completion)
                    return
                }
                self.refreshInFlight = true
                self.run(["listening-mode", "get"]) { outcome in
                    self.refreshInFlight = false
                    let waiters = self.refreshWaiters
                    self.refreshWaiters.removeAll()
                    completion(outcome)
                    for waiter in waiters { waiter(outcome) }
                }
            }
        }
    }

    // MARK: 기기 변경 감시

    /// 에어팟이 붙거나 떨어질 때 아이콘을 갱신하기 위한 리스너. 공개 CoreAudio API 만 쓴다.
    func startObservingAudioDevices() {
        guard !deviceListenerInstalled else { return }
        deviceListenerInstalled = true

        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice
        ]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
            ) { [weak self] _, _ in
                self?.scheduleDeviceChangeNotification()
            }
        }
    }

    /// 기기 하나가 바뀌어도 셀렉터 두 개에서 통지가 연달아 온다.
    /// 짧은 시간 안에 몰린 통지를 하나로 합쳐 헬퍼가 중복으로 뜨는 것을 막는다.
    private func scheduleDeviceChangeNotification() {
        pendingDeviceChange?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onAudioDevicesChanged?()
        }
        pendingDeviceChange = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    // MARK: 프로세스 실행

    private func run(_ args: [String],
                     expecting: ListeningMode? = nil,
                     completion: @escaping (EngineOutcome) -> Void) {
        helperQueue.async {
            let outcome = self.runSync(args, expecting: expecting)
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    /// 헬퍼 실행의 원시 결과.
    private enum ExecutionResult {
        case finished(status: Int32, stdout: String, stderr: String, signalled: Bool)
        case timedOut
        case launchFailed(String)
    }

    private func runSync(_ args: [String], expecting: ListeningMode? = nil) -> EngineOutcome {
        guard helperURL != nil else { return .helperMissing }

        switch execute(args) {
        case .launchFailed(let reason):
            return .failure(L10n.t("Could not run the helper: \(reason)",
                                   "헬퍼를 실행하지 못했습니다: \(reason)"))
        case .timedOut:
            return .failure(L10n.t("The helper did not respond, so the operation was cancelled.",
                                   "헬퍼가 응답하지 않아 중단했습니다."))
        case .finished(let status, let stdout, let stderr, let signalled):
            if signalled {
                // 비공개 API 에 기대는 구조라 macOS 업데이트 뒤 헬퍼가 죽을 수 있다.
                // 그때 종료 코드를 정상 오류로 읽으면 엉뚱한 안내를 하게 된다.
                return .failure(L10n.t(
                    "The helper crashed (signal \(status)). Try rebuilding it.",
                    "헬퍼가 비정상 종료했습니다 (시그널 \(status)). 다시 빌드해 보세요."))
            }
            return interpret(status: status, stdout: stdout, stderr: stderr, expecting: expecting)
        }
    }

    /// 헬퍼를 실제로 돌린다. 시한을 넘기면 끝까지 죽인다.
    private func execute(_ args: [String]) -> ExecutionResult {
        guard let helper = helperURL else {
            return .launchFailed(L10n.t("executable not found", "실행 파일 없음"))
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = args

        // 헬퍼가 스스로 dylib 을 끼워 재실행해야 하므로, 부모가 이미 표시를 달아 두면 안 된다.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "AIRPODS_CONTROL_BYPASSED")
        env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // 어떤 이유로도 입력을 기다리다 멈추지 않게 한다.
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .launchFailed(error.localizedDescription)
        }

        // 파이프 버퍼가 차서 멈추는 것을 막기 위해 양쪽을 동시에 읽는다.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        // 시한이 없으면 헬퍼 한 번이 멈출 때 앱 전체가 굳는다.
        if group.wait(timeout: .now() + helperTimeout) == .timedOut {
            process.terminate()
            if group.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 1)
            }
            if process.isRunning { process.waitUntilExit() }
            return .timedOut
        }
        process.waitUntilExit()

        let stdout = String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = String(decoding: errData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return .finished(status: process.terminationStatus,
                         stdout: stdout,
                         stderr: stderr,
                         signalled: process.terminationReason == .uncaughtSignal)
    }

    /// 헬퍼의 종료 코드와 평문 출력을 결과로 옮긴다.
    private func interpret(status: Int32,
                           stdout: String,
                           stderr: String,
                           expecting: ListeningMode?) -> EngineOutcome {
        // 0 은 성공, 3 은 이미 그 모드라 아무것도 안 한 경우다. 둘 다 모드가 확정된 상태다.
        if status == 0 || status == 3 {
            // get 과 cycle 은 착지한 모드 이름을 찍는다.
            if let mode = ListeningMode(token: stdout) { return .mode(mode) }
            // set 은 모드 대신 ok 나 no-op 을 찍으므로 요청한 모드가 곧 결과다.
            if let expecting { return .mode(expecting) }
            let shown = stdout.isEmpty ? L10n.t("(no output)", "(빈 출력)") : stdout
            return .failure(L10n.t("Could not parse the helper output: \(shown)",
                                   "헬퍼 출력을 해석하지 못했습니다: \(shown)"))
        }

        let detail = Self.firstLine(stderr.isEmpty ? stdout : stderr)
        switch status {
        case 1: return .noDevice
        case 2: return .failure(L10n.t("The helper received bad arguments. \(detail)",
                                       "헬퍼 인자가 잘못되었습니다. \(detail)"))
        case 4: return .failure(L10n.t("This device does not support that mode.",
                                       "이 기기가 지원하지 않는 모드입니다."))
        case 5: return .failure(L10n.t("Could not read the current state.",
                                       "현재 상태를 읽지 못했습니다."))
        case 6: return .failure(L10n.t("The control path is unavailable. \(detail)",
                                       "제어 경로를 쓸 수 없습니다. \(detail)"))
        case 7: return .failure(L10n.t("Could not confirm whether it was applied.",
                                       "적용됐는지 확인하지 못했습니다."))
        case 8: return .failure(L10n.t("Several target devices matched, so none was chosen.",
                                       "대상 기기가 여러 개라 하나로 좁히지 못했습니다."))
        default:
            let fallback = L10n.t("The helper exited with code \(status).",
                                  "헬퍼가 코드 \(status) 로 종료했습니다.")
            return .failure(detail.isEmpty ? fallback : detail)
        }
    }

    /// 헬퍼 stderr 는 여러 줄일 수 있다. 라벨에 넣을 수 있게 첫 줄만 쓰고 길이도 자른다.
    private static func firstLine(_ text: String) -> String {
        guard let line = text.split(separator: "\n").first.map(String.init) else { return "" }
        return line.count > 160 ? String(line.prefix(160)) + "..." : line
    }
}

/// CoreAudio HAL 의 비공개 속성으로 현재 청취 모드를 읽는다.
///
/// 공개 API 만 호출하므로 권한도 엔타이틀먼트도 필요 없다.
/// 속성이 없는 macOS 나 기기에서는 조용히 nil 을 돌려주고 헬퍼 경로로 넘어간다.
enum HALListeningMode {
    /// 'lstm'. 현재 청취 모드.
    private static let listeningModeSelector: AudioObjectPropertySelector = 0x6c73746d

    /// 기본 출력 기기를 먼저 본다. 지원 기기를 두 세트 붙였을 때
    /// 표시되는 모드와 헬퍼가 조작하는 기기가 어긋나는 것을 줄이기 위해서다.
    static func read() -> ListeningMode? {
        if let output = defaultOutputDevice(), let mode = mode(of: output) { return mode }
        for device in allDevices() {
            if let mode = mode(of: device) { return mode }
        }
        return nil
    }

    private static func mode(of device: AudioObjectID) -> ListeningMode? {
        var address = AudioObjectPropertyAddress(
            mSelector: listeningModeSelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var raw: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &raw) == noErr else { return nil }
        return ListeningMode(halRawValue: raw)
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
            device != 0 else { return nil }
        return device
    }

    private static func allDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}
