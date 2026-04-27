import Foundation
import CairnCore

/// 可序列化的窗口布局快照。schema_version 版本化,日后演进有头部。
public struct PersistedLayout: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let activeGroupIndex: Int
    public let groups: [PersistedGroup]

    public struct PersistedGroup: Codable, Equatable, Sendable {
        public let tabs: [PersistedTab]
        public let activeTabId: UUID?
    }

    public struct PersistedTab: Codable, Equatable, Sendable {
        public let id: UUID
        public let workspaceId: UUID
        public let title: String
        public let cwd: String
        public let shell: String
    }
}

/// 把 SplitCoordinator 的 live 状态变成 PersistedLayout,或反过来。
@MainActor
public enum LayoutSerializer {
    public static let currentSchemaVersion = 1

    /// live → persisted
    public static func snapshot(from coordinator: SplitCoordinator) -> PersistedLayout {
        let groups = coordinator.groups.map { group in
            PersistedLayout.PersistedGroup(
                tabs: group.tabs.map { tab in
                    PersistedLayout.PersistedTab(
                        id: tab.id,
                        workspaceId: tab.workspaceId,
                        title: tab.title,
                        cwd: tab.cwd,
                        shell: tab.shell
                    )
                },
                activeTabId: group.activeTabId
            )
        }
        return PersistedLayout(
            schemaVersion: currentSchemaVersion,
            activeGroupIndex: coordinator.activeGroupIndex,
            groups: groups
        )
    }

    /// persisted → live(PTY 全新启动)
    /// callback 里用 created.id(新 UUID,forward-ref 模式),
    /// 与 SplitCoordinator.handleTabTerminated 查的 id 一致。
    public static func restore(
        _ layout: PersistedLayout,
        into coordinator: SplitCoordinator,
        onProcessTerminated: @escaping @MainActor (UUID) -> Void
    ) {
        guard layout.schemaVersion == currentSchemaVersion else {
            // 未来 schema 演进时加 migration;v1.5 严格匹配
            return
        }
        let restoredGroups: [TabGroup] = layout.groups.map { g in
            let group = TabGroup()
            for persisted in g.tabs {
                // forward-ref 模式:session 新 id 在 factory 返回后可用,
                // callback 读 created.id(与 group.tabs 存的 id 一致)
                var created: TabSession!
                created = TabSessionFactory.create(
                    workspaceId: persisted.workspaceId,
                    shell: persisted.shell,
                    cwd: persisted.cwd,
                    onProcessTerminated: { _ in
                        onProcessTerminated(created.id)
                    }
                )
                group.appendRestoredTab(created)
            }
            // activeTabId 恢复:按 "persisted tabs 里 activeTabId 的位置" 匹配
            // (新 session UUID 与 persisted 不同)
            if let oldActive = g.activeTabId,
               let pos = g.tabs.firstIndex(where: { $0.id == oldActive }),
               pos < group.tabs.count {
                group.activateTab(id: group.tabs[pos].id)
            }
            return group
        }
        coordinator.replaceGroups(restoredGroups, activeIndex: layout.activeGroupIndex)
    }

    /// 序列化为 JSON String(用 CairnCore.jsonEncoder,ISO-8601 日期)
    public static func encode(_ layout: PersistedLayout) throws -> String {
        let data = try CairnCore.jsonEncoder.encode(layout)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public static func decode(_ json: String) throws -> PersistedLayout {
        let data = Data(json.utf8)
        return try CairnCore.jsonDecoder.decode(PersistedLayout.self, from: data)
    }
}

// 注:`load` / `save`(带 CairnDatabase)放在 CairnApp.swift,因 spec §3.2
// 约束 CairnTerminal 只能依赖 CairnCore + SwiftTerm,不能直接用 CairnStorage。
// CairnApp 作为顶层 orchestrator 同时 import 两者做桥接。
