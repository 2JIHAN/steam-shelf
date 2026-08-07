import AppKit
import Combine
import Foundation

enum SortOrder: String, CaseIterable, Identifiable {
    case name = "이름순"
    case lastPlayed = "최근 플레이순"
    case size = "용량순"

    var id: String { rawValue }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var covers: [String: NSImage] = [:]
    @Published var searchText = ""
    @Published var sortOrder: SortOrder = .lastPlayed
    @Published private(set) var isLoading = false
    @Published var isSyncing = false
    @Published var syncReport: ShortcutSync.Report?
    @Published var launchedGameID: String?

    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadTask: Task<Void, Never>?

    var steamInstalled: Bool { SteamLibrary.isSteamInstalled }

    var visibleGames: [Game] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = query.isEmpty
            ? games
            : games.filter { $0.name.lowercased().contains(query) }

        switch sortOrder {
        case .name:
            return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .lastPlayed:
            return filtered.sorted {
                let l = $0.lastPlayed ?? .distantPast
                let r = $1.lastPlayed ?? .distantPast
                if l == r { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return l > r
            }
        case .size:
            return filtered.sorted { $0.sizeOnDisk > $1.sizeOnDisk }
        }
    }

    // MARK: - 로딩

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                SteamLibrary.installedGames()
            }.value
            self.games = found
            self.isLoading = false
            self.loadCovers(for: found)
            self.startWatching()
        }
    }

    private func loadCovers(for games: [Game]) {
        for game in games where covers[game.appID] == nil {
            Task.detached(priority: .utility) {
                guard let image = Artwork.image(appID: game.appID, kind: .portrait)
                        ?? Artwork.image(appID: game.appID, kind: .header) else { return }
                await MainActor.run { self.covers[game.appID] = image }
            }
        }
    }

    // MARK: - 실행

    func launch(_ game: Game) {
        SteamLibrary.launch(game)
        launchedGameID = game.appID
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self.launchedGameID == game.appID { self.launchedGameID = nil }
        }
    }

    // MARK: - 바로가기 동기화

    func syncShortcuts() {
        guard !isSyncing else { return }
        isSyncing = true
        let snapshot = games
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                ShortcutSync.sync(games: snapshot)
            }.value
            self.syncReport = report
            self.isSyncing = false
        }
    }

    // MARK: - 라이브러리 폴더 감시 (설치/삭제 시 자동 갱신)

    private func startWatching() {
        guard watchers.isEmpty else { return }
        for root in SteamLibrary.libraryRoots() {
            let path = root.appendingPathComponent("steamapps").path
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main)
            source.setEventHandler { [weak self] in self?.scheduleReload() }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers.append(source)
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            let found = await Task.detached(priority: .utility) {
                SteamLibrary.installedGames()
            }.value
            guard Set(found.map(\.appID)) != Set(self.games.map(\.appID)) else { return }
            self.games = found
            self.loadCovers(for: found)
        }
    }
}
