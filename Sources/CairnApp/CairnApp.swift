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

    /// v1 defaultWorkspaceId(M3.5 后替换为真实)
    private let defaultWorkspaceId = UUID()

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

    /// Debounce 500ms 保存布局。反复调用会覆盖前一个 task。
    @MainActor
    private func scheduleAutoSave() {
        saveTask?.cancel()
        let snapshot = LayoutSerializer.snapshot(from: split)
        let wsId = defaultWorkspaceId
        let db = database
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let db else { return }
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
