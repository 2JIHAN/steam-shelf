import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: Store

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 22)]

    var body: some View {
        ZStack {
            backdrop
            if !store.steamInstalled {
                message("Steam이 설치되어 있지 않습니다",
                        detail: "~/Library/Application Support/Steam 경로를 찾을 수 없습니다.")
            } else if store.games.isEmpty {
                message(store.isLoading ? "라이브러리를 읽는 중…" : "설치된 게임이 없습니다",
                        detail: store.isLoading ? "" : "Steam에서 게임을 설치하면 자동으로 나타납니다.")
            } else {
                grid
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .navigationTitle("Steam Shelf")
        .navigationSubtitle(subtitle)
        .toolbar { toolbarItems }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "게임 검색")
        .onAppear { store.refresh() }
        .alert("바로가기 동기화 완료",
               isPresented: Binding(
                   get: { store.syncReport != nil },
                   set: { if !$0 { store.syncReport = nil } })) {
            Button("확인", role: .cancel) { store.syncReport = nil }
            Button("Applications 폴더 열기") {
                NSWorkspace.shared.open(ShortcutSync.applicationsDir)
                store.syncReport = nil
            }
        } message: {
            Text(store.syncReport?.summary ?? "")
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
                            Button("실행") { store.launch(game) }
                            Button("설치 폴더 열기") { SteamLibrary.revealInFinder(game) }
                            Button("상점 페이지 열기") { SteamLibrary.openStorePage(game) }
                            Divider()
                            Button("AppID 복사 (\(game.appID))") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(game.appID, forType: .string)
                            }
                        }
                }
            }
            .padding(28)
        }
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.title3.weight(.medium)).foregroundStyle(.white)
            if !detail.isEmpty {
                Text(detail).font(.callout).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// 창 제목 옆에 붙는 요약. 검색 중이면 필터 결과 수를 보여준다.
    private var subtitle: String {
        let shown = store.visibleGames.count
        let total = store.games.count
        guard total > 0 else { return "" }
        return shown == total ? "게임 \(total)개" : "게임 \(shown)개 / 전체 \(total)개"
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem {
            Picker("정렬", selection: $store.sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
        ToolbarItem {
            Button {
                store.refresh()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
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
                    Label("바로가기 동기화", systemImage: "square.and.arrow.down.on.square")
                }
            }
            .disabled(store.isSyncing || store.games.isEmpty)
            .help("설치된 게임의 .app 바로가기를 ~/Applications에 만들고, 삭제된 게임의 바로가기는 휴지통으로 옮깁니다.")
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
