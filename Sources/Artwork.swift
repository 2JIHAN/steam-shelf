import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 게임 아트워크 조회.
///
/// Steam이 이미 디스크에 받아둔 아트워크만 읽는다. 원격에서 받아오는 경로는
/// 일부러 두지 않았다. 커버를 CDN에서 받으려면 URL에 appid를 실어 보내야 하고,
/// 그건 보유 게임 목록을 밖으로 흘리는 것과 같다. 아트워크가 없는 게임은
/// 제목 타일로 표시하고, Steam을 한 번 열면 Steam이 알아서 캐시를 채운다.
enum Artwork {
    enum Kind {
        /// 600x900 세로 포스터 (그리드용)
        case portrait
        /// 460x215 가로 헤더 (아이콘 폴백용)
        case header

        var fileNames: [String] {
            switch self {
            case .portrait:
                return ["library_600x900.jpg", "library_600x900.png",
                        "library_capsule.jpg", "library_capsule.png"]
            case .header:
                return ["library_header.jpg", "library_header.png",
                        "header.jpg", "header.png"]
            }
        }
    }

    // MARK: - 조회

    /// 로컬 Steam 캐시에서 아트워크 파일을 찾는다.
    static func localURL(appID: String, kind: Kind) -> URL? {
        let fm = FileManager.default
        for root in SteamLibrary.libraryRoots() {
            let base = root.appendingPathComponent("appcache/librarycache/\(appID)")
            guard fm.fileExists(atPath: base.path) else { continue }
            // 최신 Steam은 해시 이름 하위 폴더에 파일을 넣는다.
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            var found: [String: URL] = [:]
            for case let url as URL in walker {
                found[url.lastPathComponent.lowercased()] = url
            }
            for name in kind.fileNames {
                if let hit = found[name] { return hit }
            }
        }
        return nil
    }

    /// 디스크에 있는 아트워크만 읽는다. (동기, 백그라운드에서 호출할 것)
    static func image(appID: String, kind: Kind) -> NSImage? {
        guard let url = localURL(appID: appID, kind: kind) else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - .icns 생성

    /// 커버 아트를 정사각형으로 잘라 .icns 파일로 저장한다.
    @discardableResult
    static func writeICNS(appID: String, to destination: URL) -> Bool {
        let source = image(appID: appID, kind: .portrait)
            ?? image(appID: appID, kind: .header)
        guard let source, let square = squareCrop(source, side: 1024) else { return false }

        let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.icns.identifier as CFString, sizes.count, nil
        ) else { return false }

        for size in sizes {
            guard let scaled = resize(square, to: size) else { continue }
            CGImageDestinationAddImage(dest, scaled, nil)
        }
        return CGImageDestinationFinalize(dest)
    }

    /// 중앙 정사각 크롭 + 살짝 둥근 모서리로 앱 아이콘답게 만든다.
    private static func squareCrop(_ image: NSImage, side: Int) -> CGImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let edge = min(w, h)
        // 세로 포스터는 위쪽(로고·키아트)이 더 정보량이 많다.
        let originY = h > w ? (h - edge) * 0.30 : (h - edge) / 2
        let cropRect = CGRect(x: (w - edge) / 2, y: originY, width: edge, height: edge)
        guard let cropped = cg.cropping(to: cropRect) else { return nil }

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
        ctx.draw(cropped, in: rect)
        return ctx.makeImage()
    }

    private static func resize(_ image: CGImage, to side: Int) -> CGImage? {
        guard side != image.width else { return image }
        guard let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }
}
