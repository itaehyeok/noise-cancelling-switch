// 앱 아이콘 생성기.
//
// 실행: xcrun swift Tools/makeicon.swift
// 결과: Resources/AppIcon.icns (iconutil 로 변환)
//
// SF Symbols 는 라이선스상 앱 아이콘에 쓸 수 없어서 글리프를 직접 그린다.
// 메뉴바 아이콘(waveform.slash)과 같은 개념을 손으로 옮긴 모양이다.

import AppKit
import Foundation

// MARK: 색

/// 위에서 아래로 밝은 인디고에서 짙은 남보라로.
let gradientTop = NSColor(srgbRed: 0.44, green: 0.50, blue: 1.00, alpha: 1)
let gradientBottom = NSColor(srgbRed: 0.16, green: 0.13, blue: 0.46, alpha: 1)

// MARK: 도형

/// macOS 아이콘의 둥근 사각형. 반지름 비율은 Big Sur 이후의 약 22.37% 를 따른다.
func bodyPath(in rect: CGRect) -> CGPath {
    let radius = rect.width * 0.2237
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// 왼쪽에서 오른쪽으로 잦아드는 파형. 소음이 줄어드는 모양이다.
///
/// 대각선을 겹치는 안도 만들어 봤지만 32픽셀에서 막대와 뒤엉켜 읽히지 않았다.
/// 막대 높이만으로 의미를 담는 쪽이 작은 크기에서 훨씬 선명하다.
func waveformBars(in body: CGRect) -> [CGRect] {
    let heights: [CGFloat] = [0.72, 0.54, 0.38, 0.25, 0.14]
    let barWidth = body.width * 0.100
    let gap = body.width * 0.068
    let totalWidth = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
    var x = body.midX - totalWidth / 2
    var bars: [CGRect] = []
    for h in heights {
        let height = body.height * h
        bars.append(CGRect(x: x, y: body.midY - height / 2, width: barWidth, height: height))
        x += barWidth + gap
    }
    return bars
}

// MARK: 그리기

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { fatalError("비트맵을 만들지 못했습니다") }

    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS 아이콘은 캔버스 전체를 채우지 않는다. 가장자리에 그림자 여백을 둔다.
    let inset = size * 0.095
    let body = CGRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)
    let path = bodyPath(in: body)

    // 본체 아래 옅은 그림자.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                  blur: size * 0.035,
                  color: NSColor(white: 0, alpha: 0.32).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 본체 그라디언트.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [gradientTop.cgColor, gradientBottom.cgColor] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.minY),
                               options: [])
    }

    // 위쪽에 유리 느낌의 옅은 하이라이트.
    let highlight = CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2)
    if let gloss = CGGradient(colorsSpace: space,
                              colors: [NSColor(white: 1, alpha: 0.20).cgColor,
                                       NSColor(white: 1, alpha: 0.0).cgColor] as CFArray,
                              locations: [0, 1]) {
        ctx.saveGState()
        ctx.addRect(highlight)
        ctx.clip()
        ctx.drawLinearGradient(gloss,
                               start: CGPoint(x: body.midX, y: body.maxY),
                               end: CGPoint(x: body.midX, y: body.midY),
                               options: [])
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // 파형 막대.
    let bars = waveformBars(in: body)
    let barRadius = bars[0].width / 2
    ctx.saveGState()
    ctx.setFillColor(NSColor.white.cgColor)
    for bar in bars {
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barRadius, cornerHeight: barRadius, transform: nil))
    }
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: 출력

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// (파일 이름, 픽셀 크기)
let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    let rep = drawIcon(size: size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("\(name) 을 PNG 로 바꾸지 못했습니다")
    }
    try data.write(to: iconset.appendingPathComponent(name))
}
print("아이콘셋 생성: \(iconset.path) (\(variants.count)개)")
