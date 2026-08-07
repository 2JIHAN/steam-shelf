import AppKit
import Foundation

struct Game: Identifiable, Hashable {
    let appID: String
    let name: String
    let installDir: String
    let sizeOnDisk: Int64
    let lastPlayed: Date?
    let libraryRoot: URL      // .../Steam 또는 외장 라이브러리 루트
    let installPath: URL

    var id: String { appID }

    var sizeText: String {
        guard sizeOnDisk > 0 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: sizeOnDisk, countStyle: .file)
    }

    var lastPlayedText: String {
        guard let lastPlayed else { return String(localized: "Never played") }
        let f = RelativeDateTimeFormatter()
        f.locale = .autoupdatingCurrent
        f.unitsStyle = .short
        return f.localizedString(for: lastPlayed, relativeTo: Date())
    }

    var launchURL: URL { URL(string: "steam://rungameid/\(appID)")! }
}

enum SteamLibrary {
    /// Steam 클라이언트 설치 경로
    static var steamRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam")
    }

    static var isSteamInstalled: Bool {
        FileManager.default.fileExists(atPath: steamRoot.path)
    }

    /// 도구/런타임처럼 게임이 아닌 항목
    private static let excludedAppIDs: Set<String> = [
        "228980",  // Steamworks Common Redistributables
        "1070560", // Steam Linux Runtime
        "1391110", // Steam Linux Runtime - Soldier
        "1628350", // Steam Linux Runtime - Sniper
    ]

    /// libraryfolders.vdf 를 따라 모든 라이브러리 루트를 수집한다.
    static func libraryRoots() -> [URL] {
        var roots: [URL] = [steamRoot]
        let vdf = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let node = VDF.parse(contentsOf: vdf), let folders = node["libraryfolders"] {
            for (_, entry) in folders.children {
                guard let path = entry["path"]?.stringValue, !path.isEmpty else { continue }
                let url = URL(fileURLWithPath: path)
                if !roots.contains(where: { $0.standardized.path == url.standardized.path }) {
                    roots.append(url)
                }
            }
        }
        return roots.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func installedGames() -> [Game] {
        let fm = FileManager.default
        var games: [String: Game] = [:]

        for root in libraryRoots() {
            let steamapps = root.appendingPathComponent("steamapps")
            guard let entries = try? fm.contentsOfDirectory(
                at: steamapps, includingPropertiesForKeys: nil) else { continue }

            for entry in entries where entry.lastPathComponent.hasPrefix("appmanifest_")
                && entry.pathExtension == "acf" {
                guard let node = VDF.parse(contentsOf: entry),
                      let state = node["AppState"],
                      let appID = state["appid"]?.stringValue,
                      !excludedAppIDs.contains(appID) else { continue }

                let name = state["name"]?.stringValue ?? "AppID \(appID)"
                let installDir = state["installdir"]?.stringValue ?? name
                let size = Int64(state["SizeOnDisk"]?.stringValue ?? "0") ?? 0
                let played = Int(state["LastPlayed"]?.stringValue ?? "0") ?? 0
                let installPath = steamapps
                    .appendingPathComponent("common")
                    .appendingPathComponent(installDir)

                // 실제로 설치되어 있는 것만 (다운로드 대기 중인 항목 제외)
                guard fm.fileExists(atPath: installPath.path) else { continue }

                games[appID] = Game(
                    appID: appID,
                    name: name,
                    installDir: installDir,
                    sizeOnDisk: size,
                    lastPlayed: played > 0 ? Date(timeIntervalSince1970: TimeInterval(played)) : nil,
                    libraryRoot: root,
                    installPath: installPath
                )
            }
        }
        return Array(games.values)
    }

    static func launch(_ game: Game) {
        NSWorkspace.shared.open(game.launchURL)
    }

    static func revealInFinder(_ game: Game) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: game.installPath.path)
    }

    static func openStorePage(_ game: Game) {
        NSWorkspace.shared.open(URL(string: "https://store.steampowered.com/app/\(game.appID)")!)
    }
}
