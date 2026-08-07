import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 22)]

    var body: some View {
        ZStack {
            backdrop
            if !store.steamInstalled {
                message("Steam is not installed",
                        detail: "Could not find ~/Library/Application Support/Steam.")
            } else if store.games.isEmpty {
                message(store.isLoading ? "Reading your library…" : "No games installed",
                        detail: store.isLoading
                            ? nil
                            : "Games you install in Steam appear here automatically.")
            } else {
                grid
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle("Steam Shelf")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarItems }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: Text("Search games"))
        .onAppear { store.refresh() }
        .alert("Shortcut sync complete",
               isPresented: Binding(
                   get: { store.syncReport != nil },
                   set: { if !$0 { store.syncReport = nil } })) {
            Button("OK", role: .cancel) { store.syncReport = nil }
            Button("Open Applications Folder") {
                NSWorkspace.shared.open(ShortcutSync.applicationsDir)
                store.syncReport = nil
            }
        } message: {
            Text(store.syncReport.map(SyncReportFormatter.message) ?? "")
        }
    }

    // MARK: - 구성 요소

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(red: 0.09, green: 0.11, blue: 0.15),
                     Color(red: 0.05, green: 0.06, blue: 0.09)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 26) {
                ForEach(store.visibleGames) { game in
                    GameTile(game: game, cover: store.covers[game.appID],
                             isLaunching: store.launchedGameID == game.appID)
                        .onTapGesture { store.launch(game) }
                        .contextMenu {
                            Button("Play") { store.launch(game) }
                            Button("Reveal Install Folder") { SteamLibrary.revealInFinder(game) }
                            Button("Open Store Page") { SteamLibrary.openStorePage(game) }
                            Divider()
                            Button("Copy AppID (\(game.appID))") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(game.appID, forType: .string)
                            }
                        }
                }
            }
            .padding(28)
        }
    }

    private func message(_ title: LocalizedStringKey, detail: LocalizedStringKey?) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.title3.weight(.medium)).foregroundStyle(.white)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// 창 제목 옆에 붙는 요약. 검색 중이면 필터 결과 수를 함께 보여준다.
    private var subtitle: String {
        let shown = store.visibleGames.count
        let total = store.games.count
        guard total > 0 else { return "" }
        let totalText = Self.gameCount(total)
        guard shown != total else { return totalText }
        return String(format: String(localized: "%1$lld of %2$@"), shown, totalText)
    }

    /// 영어의 단수/복수를 위해 키를 나눈다. 다른 언어는 두 키가 같은 문장을 가리킨다.
    static func gameCount(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 game")
            : String(format: String(localized: "%lld games"), count)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Picker("Sort", selection: $store.sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Button {
                store.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(store.isLoading)
        }
        ToolbarItem {
            Button {
                store.syncShortcuts()
            } label: {
                if store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Sync Shortcuts", systemImage: "square.and.arrow.down.on.square")
                }
            }
            .disabled(store.isSyncing || store.games.isEmpty)
            .help("Creates a .app shortcut in ~/Applications for every installed game, and moves shortcuts for uninstalled games to the Trash.")
        }
    }
}

// MARK: - 동기화 결과 문장 조립

/// 리포트는 구조화된 데이터로 오고, 사람이 읽을 문장은 여기서 만든다.
/// 언어마다 어순이 다르므로 조립을 코드가 아니라 포맷 문자열에 맡긴다.
enum SyncReportFormatter {
    static func message(_ report: ShortcutSync.Report) -> String {
        guard !report.isEmpty else {
            return String(localized: "Nothing to change. Your shortcuts are already up to date.")
        }
        var blocks: [String] = []
        appendBlock(&blocks, "Created (%lld)", report.created)
        appendBlock(&blocks, "Updated (%lld)", report.updated)
        appendBlock(&blocks, "Moved to Trash (%lld)", report.removed)
        appendBlock(&blocks, "Skipped (%lld)", report.skipped.map(describe))
        return blocks.joined(separator: "\n\n")
    }

    private static func appendBlock(
        _ blocks: inout [String], _ headingKey: String.LocalizationValue, _ items: [String]
    ) {
        guard !items.isEmpty else { return }
        let heading = String(format: String(localized: headingKey), items.count)
        let body = items.map { "  · \($0)" }.joined(separator: "\n")
        blocks.append("\(heading)\n\(body)")
    }

    private static func describe(_ skipped: ShortcutSync.Skipped) -> String {
        switch skipped.reason {
        case .nameTaken:
            return String(format: String(localized: "%@ — an app with that name already exists and is not a Steam shortcut"),
                          skipped.name)
        case .writeFailed(let detail):
            return String(format: String(localized: "%1$@ — could not be created: %2$@"),
                          skipped.name, detail)
        case .trashFailed(let detail):
            return String(format: String(localized: "%1$@ — could not be removed: %2$@"),
                          skipped.name, detail)
        }
    }
}

// MARK: - 타일

private struct GameTile: View {
    let game: Game
    let cover: NSImage?
    let isLaunching: Bool

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                artwork
                if hovering || isLaunching {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.black.opacity(0.45))
                    Image(systemName: isLaunching ? "hourglass" : "play.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(hovering ? 0.35 : 0.08))
            )
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.25),
                    radius: hovering ? 14 : 6, y: hovering ? 8 : 3)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(game.sizeText) · \(game.lastPlayedText)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.20, blue: 0.28),
                             Color(red: 0.10, green: 0.12, blue: 0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(game.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(12)
            }
        }
    }
}
