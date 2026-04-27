import SwiftUI
import CairnUI
import CairnTerminal
import CairnStorage

@main
struct CairnApp: App {
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true
    @State private var split = SplitCoordinator()

    /// M1.5 持久化:每次 @Observable 变化后 debounce 500ms 再写 DB
    @State private var saveTask: Task<Void, Never>?

    /// v1 defaultWorkspaceId:**hardcoded UUID**(stable across launches)。
    /// 初稿用 `UUID()` 每次启动生成新 id,导致 LayoutStateDAO.fetch 永远查不到
    /// 上次保存的布局(都是新 key)—— 恢复完全失效。
    /// M3.5 Workspace 管理就位后替换为真实 workspace id。
    private let defaultWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// 持久化用的 DB(task 里初始化)
    @State private var database: CairnDatabase?

    var body: some Scene {
        WindowGroup("Cairn", content: {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector,
                split: split
            )
            .task {
                await initializeDatabase()
            }
            // Observable 变化触发保存 debounce
            .onChange(of: split.groups.map { $0.tabs.count }) { _, _ in scheduleAutoSave() }
            .onChange(of: split.groups.flatMap { $0.tabs }.map(\.cwd)) { _, _ in scheduleAutoSave() }
            .onChange(of: split.groups.map { $0.activeTabId }) { _, _ in scheduleAutoSave() }
            .onChange(of: split.activeGroupIndex) { _, _ in scheduleAutoSave() }
        })
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Sidebar") {
                    withAnimation {
                        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Toggle Inspector") {
                    withAnimation {
                        showInspector.toggle()
                    }
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    withAnimation {
                        _ = split.activeGroup.openTab(
                            workspaceId: defaultWorkspaceId,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    withAnimation {
                        split.closeActiveTab()
                    }
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Next Tab") {
                    split.activeGroup.activateNextTab()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Previous Tab") {
                    split.activeGroup.activatePreviousTab()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                // ⌘⇧D:水平分屏(spec §6.7)
                Button("Split Horizontal") {
                    withAnimation {
                        split.splitHorizontal(
                            workspaceId: defaultWorkspaceId,
                            onProcessTerminated: { [weak split] tabId in
                                split?.handleTabTerminated(tabId: tabId)
                            }
                        )
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - 初始化 / 恢复

    @MainActor
    private func initializeDatabase() async {
        do {
            let db = try await CairnDatabase(
                location: .productionSupportDirectory,
                migrator: CairnStorage.makeMigrator()
            )
            self.database = db

            // 尝试 restore 布局
            if let layoutJson = try await LayoutStateDAO.fetch(
                workspaceId: defaultWorkspaceId, in: db
            ) {
                let layout = try LayoutSerializer.decode(layoutJson.layoutJson)
                LayoutSerializer.restore(
                    layout,
                    into: split,
                    onProcessTerminated: { [weak split] tabId in
                        split?.handleTabTerminated(tabId: tabId)
                    }
                )
            }
        } catch {
            // DB 打不开或 restore 失败,继续用空状态(不阻塞 App 启动)
            print("[CairnApp] DB init / restore failed: \(error)")
        }

        // 首次启动 or restore 后仍无 tab → 开默认
        if split.activeGroup.tabs.isEmpty {
            split.activeGroup.openTab(
                workspaceId: defaultWorkspaceId,
                onProcessTerminated: { [weak split] tabId in
                    split?.handleTabTerminated(tabId: tabId)
                }
            )
        }
    }

    // MARK: - Persistence

    /// 立即保存布局(初稿有 500ms debounce,app 退出前未完成的 task 会被
    /// 取消,最后的改动丢失 —— 这是"开 tab 关 app 不恢复"的另一大元凶)。
    /// 去掉 debounce,每次 onChange 都立即写 DB(SQLite upsert 小 JSON 行,
    /// 开销可忽略,快速连续改动最多也就几次写)。
    @MainActor
    private func scheduleAutoSave() {
        saveTask?.cancel()
        let snapshot = LayoutSerializer.snapshot(from: split)
        let wsId = defaultWorkspaceId
        guard let db = database else { return }
        saveTask = Task { @MainActor in
            do {
                let json = try LayoutSerializer.encode(snapshot)
                try await LayoutStateDAO.upsert(
                    workspaceId: wsId,
                    layoutJson: json,
                    updatedAt: Date(),
                    in: db
                )
            } catch {
                print("[CairnApp] layout save failed: \(error)")
            }
        }
    }
}
