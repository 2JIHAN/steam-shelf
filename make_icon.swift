// 앱 아이콘 생성기 — build.sh에서 한 번 실행된다.
// 확장자가 .png면 단일 PNG(1024px), 그 외에는 멀티사이즈 .icns를 쓴다.
import AppKit
import ImageIO
import UniformTypeIdentifiers

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.icns"

func draw(side: Int) -> CGImage? {
    let s = CGFloat(side)
    guard let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
    ) else { return nil }

    let inset = s * 0.055
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Steam 계열의 짙은 청록 그라디언트
    let colors = [
        CGColor(red: 0.10, green: 0.16, blue: 0.24, alpha: 1),
        CGColor(red: 0.04, green: 0.06, blue: 0.10, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: s),
                               end: CGPoint(x: s, y: 0),
                               options: [])
    }

    // 선반 위에 꽂힌 게임 커버 3장. 세로 2:3 비율에 마지막 한 장은 기대어 놓는다.
    let shelfY = s * 0.255
    let shelfH = s * 0.035
    let coverW = s * 0.185
    let coverH = coverW * 1.5
    let gap = s * 0.035
    let totalW = coverW * 3 + gap * 2
    let startX = (s - totalW) / 2

    struct Cover { let color: CGColor; let tilt: CGFloat; let scale: CGFloat }
    let covers = [
        Cover(color: CGColor(red: 0.36, green: 0.71, blue: 0.95, alpha: 1), tilt: 0, scale: 0.92),
        Cover(color: CGColor(red: 0.55, green: 0.85, blue: 0.72, alpha: 1), tilt: 0, scale: 1.0),
        Cover(color: CGColor(red: 0.98, green: 0.74, blue: 0.42, alpha: 1), tilt: -0.16, scale: 0.86),
    ]

    for (idx, cover) in covers.enumerated() {
        let w = coverW, h = coverH * cover.scale
        let x = startX + CGFloat(idx) * (coverW + gap)
        ctx.saveGState()
        // 밑변 중앙을 기준으로 기울인다.
        ctx.translateBy(x: x + w / 2, y: shelfY + shelfH)
        ctx.rotate(by: cover.tilt)
        let r = CGRect(x: -w / 2, y: 0, width: w, height: h)

        ctx.setFillColor(cover.color)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.022, cornerHeight: s * 0.022, transform: nil))
        ctx.fillPath()

        // 커버 상단 키아트 느낌의 밝은 띠
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
        let band = CGRect(x: -w / 2 + w * 0.14, y: h * 0.62, width: w * 0.72, height: h * 0.2)
        ctx.addPath(CGPath(roundedRect: band, cornerWidth: s * 0.012, cornerHeight: s * 0.012, transform: nil))
        ctx.fillPath()

        // 가운데 커버에는 재생 삼각형
        if idx == 1 {
            let t = w * 0.30
            ctx.setFillColor(CGColor(red: 0.05, green: 0.08, blue: 0.13, alpha: 0.8))
            ctx.move(to: CGPoint(x: -t * 0.4, y: h * 0.30 - t / 2))
            ctx.addLine(to: CGPoint(x: -t * 0.4, y: h * 0.30 + t / 2))
            ctx.addLine(to: CGPoint(x: t * 0.55, y: h * 0.30))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    // 선반 판 + 양쪽 지지대
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    let boardX = startX - s * 0.055
    let boardW = totalW + s * 0.11
    let board = CGRect(x: boardX, y: shelfY, width: boardW, height: shelfH)
    ctx.addPath(CGPath(roundedRect: board, cornerWidth: shelfH / 2, cornerHeight: shelfH / 2, transform: nil))
    ctx.fillPath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    for legX in [boardX + s * 0.015, boardX + boardW - s * 0.015 - shelfH * 0.8] {
        let leg = CGRect(x: legX, y: shelfY - s * 0.075, width: shelfH * 0.8, height: s * 0.08)
        ctx.addPath(CGPath(roundedRect: leg, cornerWidth: shelfH * 0.4, cornerHeight: shelfH * 0.4, transform: nil))
        ctx.fillPath()
    }

    return ctx.makeImage()
}

let url = URL(fileURLWithPath: outputPath)

if url.pathExtension.lowercased() == "png" {
    guard let image = draw(side: 1024),
          let dest = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("png destination 생성 실패")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("png 저장 실패") }
    print("아이콘 생성: \(outputPath)")
    exit(0)
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
guard let dest = CGImageDestinationCreateWithURL(
    url as CFURL, UTType.icns.identifier as CFString, sizes.count, nil) else {
    fatalError("icns destination 생성 실패")
}
for size in sizes {
    if let image = draw(side: size) {
        CGImageDestinationAddImage(dest, image, nil)
    }
}
if !CGImageDestinationFinalize(dest) {
    fatalError("icns 저장 실패")
}
print("아이콘 생성: \(outputPath)")
