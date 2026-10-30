# Noise Cancelling Switch

에어팟의 노이즈 캔슬링과 주변음 허용을 메뉴바에서 오가는 macOS 앱.

- 메뉴바 아이콘 **왼쪽 클릭**: 노이즈 캔슬링 ↔ 주변음 허용 토글
- 메뉴바 아이콘 **오른쪽 클릭**: 현재 모드 확인, 모드 직접 선택, 설정, 종료
- **앱 실행**: 설정창이 열린다. 이미 떠 있으면 다시 실행해도 설정창이 열린다
- **설정창**: 로그인 시 자동 실행, 전역 단축키 지정

적응형 모드는 토글 대상에서 뺐다. 아이폰이나 손동작으로 적응형이나 끔 상태가 되어 있어도
다음 토글에서 노이즈 캔슬링이나 주변음 허용 중 하나로 복귀한다.

단축키 기본값은 **미할당**이다. 설정창에서 직접 지정해야 작동한다.

## 요구 사항

- macOS 13 이상 (개발과 테스트는 macOS 26.5.1)
- Xcode 또는 Command Line Tools (swiftc, codesign, lipo)
- `airpods-control` 헬퍼 빌드 결과물

## 빌드

헬퍼를 먼저 빌드한다. Homebrew 설치는 Command Line Tools 버전 검사에 걸릴 수 있으므로
소스 빌드가 확실하다.

```sh
git clone --depth 1 --branch v0.4.0 https://github.com/raulgg/airpods-control.git ~/Downloads/airpods-control
cd ~/Downloads/airpods-control && make ARCHS=arm64
```

그다음 이 앱을 빌드한다. 처음 빌드할 때 헬퍼 두 파일이 `Vendor/` 로 복사되므로,
이후에는 `~/Downloads/airpods-control` 이 없어져도 된다.

```sh
git clone https://github.com/itaehyeok/noise-cancelling-switch.git
cd noise-cancelling-switch
./build.sh            # 빌드만
./build.sh run        # 빌드 후 실행
./build.sh install    # 빌드 후 /Applications 에 설치
./build.sh clean
```

헬퍼 위치가 다르면 지정할 수 있다.

```sh
HELPER_DIR=/path/to/airpods-control/build ./build.sh
```

`Vendor/` 는 git 에 올리지 않는다. 다른 기계에서 클론했다면 위 헬퍼 빌드부터 다시 해야 한다.

## 이름 바꾸기

표시 이름은 `Sources/AppInfo.swift` 의 `AppInfo.name` 한 곳에만 있다. 화면 문구는 전부 이 값을 쓴다.
이름을 바꾸려면 그 값과 `Resources/Info.plist` 의 `CFBundleName` / `CFBundleDisplayName` /
`CFBundleIdentifier` / `CFBundleExecutable`, `build.sh` 의 `APP_NAME` / `EXECUTABLE` 을 맞추면 된다.

**번들 ID 를 바꾸기 전에 설정창에서 자동 실행을 먼저 꺼야 한다.** 그러지 않으면 예전 번들 ID 로
등록된 로그인 항목이 고아로 남아 시스템 설정에 깨진 항목으로 보인다.
저장된 단축키와 언어도 번들 ID 별로 따로 저장되므로 `defaults` 로 옮겨 줘야 한다.

## 표시 언어

설정창 맨 위에서 English 와 한국어 중에 고른다. 바꾸면 앱을 다시 켜지 않아도 바로 반영된다.
기본값은 English 다.

문자열은 `.lproj` 번들 대신 `Sources/Localization.swift` 의 `L10n.t(english, korean)` 로
호출 지점에 두 언어를 나란히 적는 방식이다. 문자열이 백여 개뿐이라 키 테이블을 따로 두면
누락과 오타만 늘고, 이 방식이라야 앱 재시작 없이 언어를 바꿀 수 있다.

언어를 바꾸면 설정창은 통째로 다시 만들어진다. 라벨 열 폭도 그때 새 언어의 가장 긴 라벨에
맞춰 다시 계산된다. 메뉴바 메뉴는 열 때마다 새로 만들므로 따로 할 일이 없고,
⌘W / ⌘Q 를 위한 메인 메뉴만 다시 만든다.

## 앱 아이콘

`Resources/AppIcon.icns` 가 빌드 때 번들에 들어간다. 이미 만들어져 있으므로 보통은 건드릴 일이 없다.
모양을 바꾸고 싶으면 생성기를 고쳐 다시 만든다.

```sh
xcrun swift Tools/makeicon.swift
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

글리프는 왼쪽에서 오른쪽으로 잦아드는 막대 파형이다. 소음이 줄어드는 모양을 뜻한다.
대각선을 겹치는 안도 만들어 봤지만 32픽셀에서 막대와 뒤엉켜 읽히지 않아 버렸다.
SF Symbols 는 라이선스상 앱 아이콘에 쓸 수 없어 직접 그린다.

## 로그인 시 자동 실행

`SMAppService` 를 쓴다. 앱이 자주 옮겨 다니면 launchd 에 등록된 경로가 낡아 실패할 수 있으므로,
자동 실행을 쓸 거면 `./build.sh install` 로 `/Applications` 에 두고 거기서 실행하는 편이 안전하다.

## 구조

```
Noise Cancelling Switch.app/Contents/
  MacOS/NoiseCancellingSwitch  앱 본체
  Resources/airpods-control    제어 헬퍼
  Resources/avbypass.dylib     헬퍼가 쓰는 엔타이틀먼트 우회 라이브러리
```

- **쓰기**(모드 변경)는 헬퍼를 서브프로세스로 실행해서 한다.
  헬퍼가 비공개 AVFoundation 경로와 CoreAudio HAL 경로 중 적절한 쪽을 알아서 고른다.
- **읽기**(현재 모드)는 CoreAudio HAL 의 비공개 속성 `lstm` 을 먼저 시도한다.
  공개 API 만 쓰고 프로세스도 안 띄우므로 사실상 공짜다. 이게 안 되면 헬퍼에게 묻는다.
- **전역 단축키**는 Carbon 의 `RegisterEventHotKey` 로 잡는다. 접근성 권한이 필요 없다.
- 유휴 상태에서는 서브프로세스를 띄우지 않는다. 5초마다 도는 것은 HAL 읽기뿐이다.

## 빌드 설정에서 건드리면 안 되는 것

**하드닝 런타임을 켜지 마라.** 헬퍼가 `DYLD_INSERT_LIBRARIES` 로 자기 자신을 재실행해야 하는데,
하드닝 런타임이 켜지면 그 환경변수가 무시되어 조용히 실패한다. 그래서 ad-hoc 서명만 한다.
같은 이유로 앱 스토어 배포와 공증은 불가능하다. 개인용 빌드 전용이다.

## 반응 속도

단축키나 클릭 직후 메뉴바 아이콘은 **즉시** 바뀐다. 헬퍼 응답을 기다리지 않고
예상 결과를 먼저 표시하고, 응답이 오면 바로잡기 때문이다.

실제 모드 변경은 헬퍼 프로세스를 거치므로 시간이 더 걸린다. 측정값은 이렇다.

| 구간 | 소요 |
| --- | --- |
| CoreAudio HAL 로 현재 모드 읽기 | 5~6 ms |
| 헬퍼로 토글 (보통) | 78~92 ms |
| 헬퍼로 토글 (느릴 때) | 약 750 ms |

느린 경우가 왜 생기는지는 확정하지 못했다. 확인한 것은 이렇다.
유휴 시간 때문은 아니다(90초, 120초 방치 후에도 100~130ms).
프로세스마다 첫 서브프로세스 실행이 느린 것도 아니다(새 프로세스 3회 모두 79ms).
남은 가설은 에어팟과의 통신 세션이 한동안 놀다가 다시 깨어날 때 드는 비용인데,
기기를 연결한 상태에서 간격을 두고 재봐야 확정할 수 있다.

어느 쪽이든 아이콘은 이 시간과 무관하게 즉시 바뀐다.

## 알려진 업스트림 버그

`airpods-control` v0.4.0 의 `status` 명령은 이 기계에서 SIGABRT 로 죽는다(exit 134).
입력 전용 블루투스 엔드포인트를 훑는 도중 죽는 것으로 보인다.
`listening-mode get` / `set` / `cycle` 은 정상이므로 이 앱의 기능에는 영향이 없다.
그래서 이 앱은 진단에도 `status` 를 쓰지 않고 `listening-mode get --debug` 를 쓴다.

## 한계

- 비공개 API 에 의존하므로 macOS 업데이트로 깨질 수 있다.
  깨지면 `airpods-control` 을 새 버전으로 다시 빌드한 뒤 `./build.sh vendor && ./build.sh` 로
  갱신하면 되는 경우가 많다. `./build.sh` 만으로는 `Vendor/` 가 갱신되지 않는다.
- 에어팟이 연결되어 있지 않으면 메뉴바 아이콘이 흐리게 표시되고 토글은 아무 일도 하지 않는다.
- `RegisterEventHotKey` 는 다른 앱이 이미 쓰는 조합도 거절하지 않는다.
  따라서 "이 단축키는 이미 사용 중" 을 앱이 미리 알려줄 방법이 없다. 직접 눌러 확인해야 한다.
- 자동 실행을 켜 두면 앱을 실행해도 설정창이 자동으로 뜨지 않는다.
  로그인 실행과 수동 실행을 구별하는 믿을 만한 방법이 없어서 그렇게 정했다.
  설정창은 메뉴바 아이콘 우클릭에서 열거나, 앱이 이미 떠 있는 상태에서 다시 실행하면 열린다.
