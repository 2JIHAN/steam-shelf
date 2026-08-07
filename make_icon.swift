// 앱 아이콘(.icns) 생성기 — build.sh에서 한 번 실행된다.
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

    // 선반 위의 게임 커버 3장
    let coverColors = [
        CGColor(red: 0.36, green: 0.71, blue: 0.95, alpha: 1),
        CGColor(red: 0.55, green: 0.85, blue: 0.72, alpha: 1),
        CGColor(red: 0.98, green: 0.74, blue: 0.42, alpha: 1),
    ]
    let coverW = s * 0.16
    let gap = s * 0.055
    let totalW = coverW * 3 + gap * 2
    var x = (s - totalW) / 2
    let heights: [CGFloat] = [0.40, 0.50, 0.34]
    for (idx, color) in coverColors.enumerated() {
        let h = s * heights[idx]
        let r = CGRect(x: x, y: s * 0.30, width: coverW, height: h)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil))
        ctx.fillPath()
        x += coverW + gap
    }

    // 선반 바닥
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    let shelf = CGRect(x: (s - totalW) / 2 - s * 0.04, y: s * 0.255,
                       width: totalW + s * 0.08, height: s * 0.035)
    ctx.addPath(CGPath(roundedRect: shelf, cornerWidth: s * 0.017, cornerHeight: s * 0.017, transform: nil))
    ctx.fillPath()

    return ctx.makeImage()
}

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let url = URL(fileURLWithPath: outputPath)
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
