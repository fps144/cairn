import SwiftUI
import AppKit
import CairnCore
import CairnUI
import CairnTerminal
import CairnStorage
import CairnClaude

/// AppKit 代理。单一持久化入口:持有 `database` + `split` 引用,
/// 暴露 `saveLayoutNow()` 给 SwiftUI onChange 和 `applicationWillTerminate`。
///
/// 为什么用 class delegate 而不是 `@State`:
/// - 之前把 `database` 存在 App struct 的 `@State` 上,但 App 是 value type,
///   struct 方法捕获的 self 和 @State underlying storage 之间的时序在某些
///   路径下不可靠 —— 实测 `~/Library/Application Support/Cairn/cairn.sqlite`
///   的 `layout_states` 表始终为空,save 从未成功落盘。
/// - 改由一个 `final class` delegate 统一持有 DB + split 引用,就没有 value-type
///   复制 / SwiftUI state wrapper 时序问题。
/// - 同时在 `applicationWillTerminate` 补一次保底 `saveLayoutNow`,
///   即使增量 onChange 一个没触发,Cmd+Q 前也一定落盘一次。
@MainActor
final class CairnAppDelegate: NSObject, NSApplicationDelegate {
    var database: CairnDatabase?
    /// SplitCoordinator 由 App 在 .task 里注入;delegate 弱引用以免循环持有。
    weak var split: SplitCoordinator?
    /// M2.1 dev-only JSONLWatcher,由 CAIRN_DEV_WATCH=1 env var 在 initialize 里挂。
    var jsonlWatcher: JSONLWatcher?

    /// v1 defaultWorkspaceId:硬编码 UUID,跨启动稳定。M3.5 Workspace 管理
    /// 就位后替换为真实 workspace id。
    let defaultWorkspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// **同步**保存布局到 SQLite。主线程 ms 级,可接受。
    /// 在 onChange 回调 + applicationWillTerminate 里调用。
    func saveLayoutNow(reason: String) {
        guard let db = database, let split = split else {
            FileHandle.standardError.write(Data(
                "[CairnApp] save skipped (\(reason)): db=\(database != nil) split=\(split != nil)\n".utf8
            ))
            return
        }
        let snapshot = LayoutSerializer.snapshot(from: split)
        do {
            let json = try LayoutSerializer.encode(snapshot)
            try LayoutStateDAO.upsertSync(
                workspaceId: defaultWorkspaceId,
                layoutJson: json,
                updatedAt: Date(),
                in: db
            )
            FileHandle.standardError.write(Data(
                "[CairnApp] saved layout (\(reason), \(json.count) bytes)\n".utf8
            ))
        } catch {
            FileHandle.standardError.write(Data(
                "[CairnApp] save failed (\(reason)): \(error)\n".utf8
            ))
        }
    }

    /// Cmd+Q / 关窗退出前的最后保底。applicationWillTerminate 在 main thread
    /// 同步回调,可直接同步写盘。
    nonisolated func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            saveLayoutNow(reason: "willTerminate")
            // watcher.stop() 是 async,会起 Task;进程即将退出,可能跑不完。
            // 但 cursor 每 chunk 已写盘,丢最后一块可接受(Known limitations)。
            if let watcher = jsonlWatcher {
                Task { await watcher.stop() }
            }
        }
    }
}

@main
struct CairnApp: App {
    @NSApplicationDelegateAdaptor(CairnAppDelegate.self) var appDelegate

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showInspector: Bool = true
    @State private var split = SplitCoordinator()

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
            // 任意 @Observable 变化 → 立即同步写盘。
            .onChange(of: split.groups.map { $0.tabs.count }) { _, _ in
                appDelegate.saveLayoutNow(reason: "tabs.count")
            }
            .onChange(of: split.groups.flatMap { $0.tabs }.map(\.cwd)) { _, _ in
                appDelegate.saveLayoutNow(reason: "cwd")
            }
            .onChange(of: split.groups.map { $0.activeTabId }) { _, _ in
                appDelegate.saveLayoutNow(reason: "activeTabId")
            }
            .onChange(of: split.activeGroupIndex) { _, _ in
                appDelegate.saveLayoutNow(reason: "activeGroupIndex")
            }
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
                            workspaceId: appDelegate.defaultWorkspaceId,
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
                            workspaceId: appDelegate.defaultWorkspaceId,
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
        appDelegate.split = split
        do {
            let db = try await CairnDatabase(
                location: .productionSupportDirectory,
                migrator: CairnStorage.makeMigrator()
            )
            appDelegate.database = db
            FileHandle.standardError.write(Data("[CairnApp] DB opened\n".utf8))

            // 必须先确保默认 workspace 行存在。layout_states.workspace_id 有
            // FK 到 workspaces(id),不 upsert 这行会让后续 save 全部被 FK 拒
            // (SQLite error 19 FOREIGN KEY constraint failed)。
            // M3.5 接真实 Workspace 管理后,这段 bootstrap 拆到 workspace
            // onboarding 流程里。
            let defaultWs = Workspace(
                id: appDelegate.defaultWorkspaceId,
                name: "Default",
                cwd: NSHomeDirectory()
            )
            try await WorkspaceDAO.upsert(defaultWs, in: db)
            FileHandle.standardError.write(Data(
                "[CairnApp] ensured default workspace\n".utf8
            ))

            // 尝试 restore 布局
            if let layoutJson = try await LayoutStateDAO.fetch(
                workspaceId: appDelegate.defaultWorkspaceId, in: db
            ) {
                let layout = try LayoutSerializer.decode(layoutJson.layoutJson)
                LayoutSerializer.restore(
                    layout,
                    into: split,
                    onProcessTerminated: { [weak split] tabId in
                        split?.handleTabTerminated(tabId: tabId)
                    }
                )
                FileHandle.standardError.write(Data(
                    "[CairnApp] restored \(layout.groups.count) group(s), \(layout.groups.reduce(0) { $0 + $1.tabs.count }) tab(s)\n".utf8
                ))
            } else {
                FileHandle.standardError.write(Data("[CairnApp] no saved layout\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data(
                "[CairnApp] DB init / restore failed: \(error)\n".utf8
            ))
        }

        // 首次启动 or restore 后仍无 tab → 开默认
        if split.activeGroup.tabs.isEmpty {
            split.activeGroup.openTab(
                workspaceId: appDelegate.defaultWorkspaceId,
                onProcessTerminated: { [weak split] tabId in
                    split?.handleTabTerminated(tabId: tabId)
                }
            )
        }

        // M2.1 dev-only harness:CAIRN_DEV_WATCH=1 启动 JSONLWatcher 并 stderr
        // 打印事件流。不接 UI,不写 events 表 —— 只验证 watcher 在真实 Claude
        // session 上跑得起来。M2.3 才真正接入 ingestor。
        if ProcessInfo.processInfo.environment["CAIRN_DEV_WATCH"] == "1",
           let db = appDelegate.database {
            let root = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
            let watcher = JSONLWatcher(
                database: db,
                projectsRoot: root,
                defaultWorkspaceId: appDelegate.defaultWorkspaceId
            )
            appDelegate.jsonlWatcher = watcher
            // events() 必须在 start() 之前订阅,否则漏 .discovered 初始事件。
            let stream = await watcher.events()
            Task {
                for await event in stream {
                    switch event {
                    case .discovered(let s):
                        FileHandle.standardError.write(Data(
                            "[JSONLWatcher] discovered \(s.id) at \(s.jsonlPath)\n".utf8
                        ))
                    case .lines(let sid, let ls, let start, _):
                        FileHandle.standardError.write(Data(
                            "[JSONLWatcher] +\(ls.count) lines for \(sid) (from #\(start))\n".utf8
                        ))
                    case .removed(let sid):
                        FileHandle.standardError.write(Data(
                            "[JSONLWatcher] removed \(sid)\n".utf8
                        ))
                    }
                }
            }
            do {
                try await watcher.start()
                FileHandle.standardError.write(Data(
                    "[JSONLWatcher] started on \(root.path)\n".utf8
                ))
            } catch {
                FileHandle.standardError.write(Data(
                    "[JSONLWatcher] start failed: \(error)\n".utf8
                ))
            }
        }
    }
}
