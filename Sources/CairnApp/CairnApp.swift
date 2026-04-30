import SwiftUI
import AppKit
import CairnCore
import CairnUI
import CairnTerminal
import CairnStorage
import CairnClaude
import CairnServices

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
    /// M2.1 JSONLWatcher。M2.4 起正式化(非 env-gated),每次启动都起。
    var jsonlWatcher: JSONLWatcher?
    /// M2.3 EventIngestor。M2.4 起正式化。
    var eventIngestor: EventIngestor?
    /// M2.4 TimelineViewModel —— delegate 持生命周期版(willTerminate stop)。
    /// 另外 App struct 用 @State 持一份供 SwiftUI UI 观察,赋值时触发 body 重渲。
    var timelineVM: TimelineViewModel?
    /// M2.6 Tab↔Session broker(按 cwd 绑 tab)
    var broker: TabSessionBroker?
    /// M2.6 Session lifecycle monitor(30s tick + 5 态机)
    var lifecycleMonitor: SessionLifecycleMonitor?

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
            // 停止顺序(反向启动顺序):vm → broker → monitor → ingestor → watcher。
            // vm.stop 同步;其他 async,起 Task 但进程可能来不及跑完。
            // cursor 每 chunk 已写盘,丢最后一块可接受。
            timelineVM?.stop()
            if let broker = broker {
                Task { await broker.stop() }
            }
            if let monitor = lifecycleMonitor {
                Task { await monitor.stop() }
            }
            if let ingestor = eventIngestor {
                Task { await ingestor.stop() }
            }
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
    /// M2.4 双持:delegate 持生命周期版,@State 持 UI 观察版。
    /// initializeDatabase 里同时 set 两处。
    @State private var timelineVM: TimelineViewModel?

    var body: some Scene {
        WindowGroup("Cairn", content: {
            MainWindowView(
                columnVisibility: $columnVisibility,
                showInspector: $showInspector,
                split: split,
                timelineVM: timelineVM
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

            // M2.5:独立 Events 菜单。CommandMenu 在 menu bar 建顶层菜单
            // (通常显示在 View 和 Window 之间)。
            // T15 第二轮:快捷键 ⌘⇧E 与系统/其他 app 冲突(Mail/Xcode/浏览器
            // 常见占用),换为 ⌘⌥E(Command + Option + E)避开。spec §6.7
            // 原定 ⌘⇧E,执行时调整 —— 待 M2.7 统一审校所有快捷键冲突。
            CommandMenu("Events") {
                Button("Expand / Collapse All") {
                    appDelegate.timelineVM?.toggleExpandAll()
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
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

        // M2.4:JSONLWatcher + EventIngestor + TimelineViewModel 正式启动。
        // 不再 env-gated,每次 App 启动都起 —— 这是 Cairn 的核心能力。
        // CAIRN_DEV_WATCH=1 仍保留为"额外 stderr 日志"模式,开发 debug 用。
        guard let db = appDelegate.database else { return }
        let root = URL(fileURLWithPath: "\(NSHomeDirectory())/.claude/projects")
        let watcher = JSONLWatcher(
            database: db,
            projectsRoot: root,
            defaultWorkspaceId: appDelegate.defaultWorkspaceId
        )
        let ingestor = EventIngestor(database: db, watcher: watcher)
        let vm = TimelineViewModel(ingestor: ingestor, database: db)

        // 双持:delegate(生命周期)+ @State(UI 观察)
        appDelegate.jsonlWatcher = watcher
        appDelegate.eventIngestor = ingestor
        appDelegate.timelineVM = vm
        self.timelineVM = vm  // ← 触发 SwiftUI 重渲 RightPanelView

        // M2.6:TabSessionBroker + SessionLifecycleMonitor
        let broker = TabSessionBroker(
            split: split, watcher: watcher,
            onBind: { [weak vm, split] tab, sessionId in
                // 绑定后若此 tab 正在 active,立即切 vm 到新 session
                // (.task(id:) 也会触发,但让 broker 在绑定同 event loop 里主动切,
                //  "新 session 第一刻"无延迟)
                if tab.id == split.groups[split.activeGroupIndex].activeTabId {
                    Task { @MainActor in
                        await vm?.switchSession(sessionId)
                    }
                }
            }
        )
        let monitor = SessionLifecycleMonitor(database: db)
        appDelegate.broker = broker
        appDelegate.lifecycleMonitor = monitor

        // 顺序关键:订阅源在 emit 之前。
        // vm → broker → monitor → ingestor → watcher
        await vm.start()
        await broker.start()
        await monitor.start()

        // 订阅 monitor.events 更新 vm.currentSessionState
        let stateStream = await monitor.events()
        Task { @MainActor [weak vm] in
            for await change in stateStream {
                guard let vm = vm else { break }
                if change.sessionId == vm.currentSessionId {
                    vm.updateSessionState(change.newState)
                }
            }
        }

        await ingestor.start()

        // 可选 dev stderr 日志
        if ProcessInfo.processInfo.environment["CAIRN_DEV_WATCH"] == "1" {
            let stream = await ingestor.events()
            Task {
                var persistedCount = 0
                for await event in stream {
                    switch event {
                    case .persisted:
                        persistedCount += 1
                        if persistedCount.isMultiple(of: 100) {
                            FileHandle.standardError.write(Data(
                                "[Ingestor] persisted \(persistedCount) events\n".utf8
                            ))
                        }
                    case .restored(let sid, let events):
                        FileHandle.standardError.write(Data(
                            "[Ingestor] restored \(events.count) events for \(sid)\n".utf8
                        ))
                    case .error(let sid, let start, let err):
                        FileHandle.standardError.write(Data(
                            "[Ingestor] error on \(sid) from #\(start): \(err)\n".utf8
                        ))
                    }
                }
            }
        }

        do {
            try await watcher.start()
        } catch {
            FileHandle.standardError.write(Data(
                "[Ingestor] watcher start failed: \(error)\n".utf8
            ))
        }
    }
}
