import Foundation
import Observation
import CairnCore
import CairnTerminal
import CairnClaude

/// 绑定 Cairn Tab 到 Claude Session 的 broker。
///
/// 订阅 `JSONLWatcher.events()` 的 `.discovered` 事件,按 cwd 相等匹配到
/// 最近活跃的 tab(未绑定的)并绑定。绑定后通过 onBind 回调通知外部。
///
/// 策略(spec §8.5 M2.6):
/// - **只绑 mtime < 2min 的新鲜 session**(防止 startup 494 历史 session 全
///   discovered 时 broker 反复覆盖 active tab)
/// - **cwd 匹配优先**:扫 JSONL 前 20 行找 `type=system` 的 cwd(M0.1 Q1)
/// - **已绑 tab 不覆盖**:尊重现有绑定
/// - **fallback**:无 cwd 匹配时绑 active tab → active group → 其他 group 首个未绑
/// - **symlink normalize**:`/tmp` vs `/private/tmp` 统一
@Observable
@MainActor
public final class TabSessionBroker {
    private weak var split: SplitCoordinator?
    private let watcher: JSONLWatcher
    private let onBind: @MainActor (TabSession, UUID) -> Void

    private var consumerTask: Task<Void, Never>?
    /// 已处理过的 sessionId(绑了或主动跳过),防止重复扫
    private var seenSessionIds: Set<UUID> = []

    public init(
        split: SplitCoordinator,
        watcher: JSONLWatcher,
        onBind: @escaping @MainActor (TabSession, UUID) -> Void
    ) {
        self.split = split
        self.watcher = watcher
        self.onBind = onBind
    }

    public func start() async {
        guard consumerTask == nil else { return }
        let stream = await watcher.events()
        consumerTask = Task { @MainActor [weak self] in
            for await event in stream {
                if case .discovered(let session) = event {
                    await self?.handleDiscovered(session)
                }
            }
        }
    }

    public func stop() async {
        consumerTask?.cancel()
        consumerTask = nil
    }

    // MARK: - 绑定逻辑

    func handleDiscovered(_ session: Session) async {
        guard !seenSessionIds.contains(session.id) else { return }
        guard let split = split else { return }

        // 🚧 只绑新鲜 session(mtime < 2min)
        let url = URL(fileURLWithPath: session.jsonlPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date) ?? session.startedAt
        guard Date().timeIntervalSince(mtime) < 120 else {
            seenSessionIds.insert(session.id)
            return
        }

        // 候选 tabs 按优先级:active tab → active group 其他 → 其他 group
        let orderedTabs: [TabSession] = {
            guard split.activeGroupIndex < split.groups.count else { return [] }
            var result: [TabSession] = []
            let activeGroup = split.groups[split.activeGroupIndex]
            if let at = activeGroup.activeTab { result.append(at) }
            result.append(contentsOf: activeGroup.tabs.filter { $0.id != activeGroup.activeTabId })
            for (i, g) in split.groups.enumerated() where i != split.activeGroupIndex {
                result.append(contentsOf: g.tabs)
            }
            return result
        }()
        if orderedTabs.isEmpty { return }

        // **只 cwd 精确匹配**(T17 用户反馈修订):
        // 去掉 fallback "第一个未绑 tab" 逻辑 —— 否则外部 Claude(Trae / iTerm
        // 里跑的,mtime 新鲜,cwd 不在 Cairn 任何 tab 下)会错绑到 Cairn 的
        // active tab,让 Timeline 显示外部 session 的 events。
        // 现在:无 cwd 精确匹配就不绑,session 留 DB 不进 UI。
        let sessionCwd = await resolveSessionCwd(session)
        guard let sCwd = sessionCwd else {
            seenSessionIds.insert(session.id)
            return
        }
        let normalizedSessionCwd = Self.normalize(sCwd)
        let cwdMatched = orderedTabs.first { tab in
            tab.boundClaudeSessionId == nil
                && Self.normalize(tab.cwd) == normalizedSessionCwd
        }
        guard let tab = cwdMatched else {
            seenSessionIds.insert(session.id)
            return
        }

        seenSessionIds.insert(session.id)
        tab.bindClaudeSession(session.id)
        onBind(tab, session.id)
    }

    /// 从 JSONL 文件前 N 行找 `type=system` 的 cwd(M0.1 probe Q1 规则)。
    /// **`nonisolated`** — 磁盘 I/O + JSON parse 在 cooperative thread pool 跑,
    /// 不阻塞 MainActor/UI。
    private nonisolated func resolveSessionCwd(_ session: Session) async -> String? {
        let url = URL(fileURLWithPath: session.jsonlPath)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let maxBytes = min(data.count, 16 * 1024)
        let prefix = data.prefix(maxBytes)
        guard let text = String(data: prefix, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(20) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String,
                  type == "system",
                  let cwd = obj["cwd"] as? String
            else { continue }
            return cwd
        }
        return nil
    }

    /// macOS `/tmp` → `/private/tmp` 等 symlink 统一。
    private static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
