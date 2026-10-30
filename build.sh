#!/bin/sh
# NoCan 빌드 스크립트.
# Xcode 프로젝트 없이 swiftc 로 직접 컴파일하고 .app 번들을 조립한다.
#
# 중요: 하드닝 런타임을 켜지 않는다. 번들 안의 헬퍼(airpods-control)가
# DYLD_INSERT_LIBRARIES 로 자기 자신을 재실행해야 하는데, 하드닝 런타임이
# 켜지면 그 환경변수가 무시되어 조용히 실패한다. 그래서 ad-hoc 서명만 한다.
set -eu

cd "$(dirname "$0")"

# 번들 이름에는 공백이 들어간다. 실행 파일 이름은 공백 없이 따로 둔다.
APP_NAME="Noise Cancelling Switch"
EXECUTABLE="NoiseCancellingSwitch"
BUILD_DIR="${BUILD_DIR:-build}"
APP="$BUILD_DIR/$APP_NAME.app"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"
HELPER_DIR="${HELPER_DIR:-$HOME/Downloads/airpods-control/build}"
VENDOR_DIR="Vendor"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

ARCH="$(uname -m)"

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

vendor_helpers() {
  if [ -x "$VENDOR_DIR/airpods-control" ] && [ -f "$VENDOR_DIR/avbypass.dylib" ]; then
    return 0
  fi
  log "헬퍼를 $HELPER_DIR 에서 가져오는 중..."
  [ -x "$HELPER_DIR/airpods-control" ] || die "airpods-control 을 찾을 수 없습니다: $HELPER_DIR
  먼저 빌드하세요:
    git clone --depth 1 --branch v0.4.0 https://github.com/raulgg/airpods-control.git ~/Downloads/airpods-control
    cd ~/Downloads/airpods-control && make ARCHS=arm64
  또는 HELPER_DIR 를 직접 지정하세요: HELPER_DIR=/path/to/build ./build.sh"
  [ -f "$HELPER_DIR/avbypass.dylib" ] || die "avbypass.dylib 을 찾을 수 없습니다: $HELPER_DIR"
  # 앱은 이 기계의 아키텍처로만 컴파일된다. 헬퍼가 다른 아키텍처면
  # 번들은 멀쩡히 만들어지는데 토글만 조용히 실패한다.
  file "$HELPER_DIR/airpods-control" | grep -q "$ARCH" \
    || die "헬퍼 아키텍처가 이 기계($ARCH)와 다릅니다:
  $(file "$HELPER_DIR/airpods-control")
  airpods-control 을 ARCHS=$ARCH 로 다시 빌드하세요."
  file "$HELPER_DIR/avbypass.dylib" | grep -q "$ARCH" \
    || die "avbypass.dylib 아키텍처가 이 기계($ARCH)와 다릅니다."

  mkdir -p "$VENDOR_DIR"
  cp "$HELPER_DIR/airpods-control" "$VENDOR_DIR/"
  cp "$HELPER_DIR/avbypass.dylib" "$VENDOR_DIR/"
  chmod +x "$VENDOR_DIR/airpods-control"
  log "헬퍼를 $VENDOR_DIR 에 복사했습니다. 이제 원본 위치가 없어져도 됩니다."
}

build_app() {
  vendor_helpers

  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

  cp Resources/Info.plist "$APP/Contents/Info.plist"
  # 아이콘이 없으면 시스템 설정의 로그인 항목 등에서 회색 자리표시자로 뜬다.
  if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
  else
    log "경고: Resources/AppIcon.icns 가 없습니다. xcrun swift Tools/makeicon.swift 로 만드세요."
  fi
  printf 'APPL????' > "$APP/Contents/PkgInfo"

  log "Swift 컴파일 중 ($ARCH)..."
  # shellcheck disable=SC2046
  xcrun swiftc -O \
    -target "$ARCH-apple-macos$DEPLOYMENT_TARGET" \
    -framework AppKit \
    -framework Carbon \
    -framework CoreAudio \
    -framework ServiceManagement \
    -o "$APP/Contents/MacOS/$EXECUTABLE" \
    Sources/*.swift

  # 헬퍼와 dylib 은 반드시 같은 디렉터리에 있어야 한다.
  # 헬퍼가 자기 실행 파일 경로 옆에서 dylib 을 찾기 때문이다.
  cp "$VENDOR_DIR/airpods-control" "$APP/Contents/Resources/"
  cp "$VENDOR_DIR/avbypass.dylib" "$APP/Contents/Resources/"
  chmod +x "$APP/Contents/Resources/airpods-control"

  log "ad-hoc 서명 중..."
  codesign --force --sign - "$APP/Contents/Resources/avbypass.dylib"
  codesign --force --sign - "$APP/Contents/Resources/airpods-control"
  codesign --force --sign - "$APP"

  log "빌드 완료: $APP"
}

case "${1:-build}" in
  build)
    build_app
    ;;
  run)
    build_app
    log "실행 중인 인스턴스를 종료합니다..."
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    sleep 1
    open "$APP"
    log "실행했습니다. 메뉴바를 확인하세요."
    ;;
  install)
    build_app
    log "$INSTALL_DIR 로 설치합니다..."
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
    cp -R "$APP" "$INSTALL_DIR/"
    log "설치 완료: $INSTALL_DIR/$APP_NAME.app"
    log "로그인 항목 자동 실행을 쓰려면 이 위치에서 실행하세요."
    ;;
  vendor)
    log "번들된 헬퍼를 버리고 $HELPER_DIR 에서 다시 가져옵니다..."
    rm -f "$VENDOR_DIR/airpods-control" "$VENDOR_DIR/avbypass.dylib"
    vendor_helpers
    log "이제 ./build.sh 로 다시 빌드하세요."
    ;;
  clean)
    rm -rf "$BUILD_DIR"
    log "정리했습니다. 번들된 헬퍼까지 새로 받으려면 ./build.sh vendor 를 쓰세요."
    ;;
  *)
    die "사용법: ./build.sh [build|run|install|vendor|clean]"
    ;;
esac
