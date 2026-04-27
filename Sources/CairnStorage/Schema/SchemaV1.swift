import Foundation

/// v1 schema 的 CREATE TABLE + CREATE INDEX SQL。
/// 严格对齐 spec §D,补 spec §2.6 / M1.1 struct 的 `sessions.is_imported` 列。
enum SchemaV1 {
    /// 所有 DDL,按 FK 依赖顺序排列。
    static let statements: [String] = [
        // workspaces(无 FK)
        """
        CREATE TABLE workspaces (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            cwd TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP NOT NULL,
            last_active_at TIMESTAMP NOT NULL,
            archived_at TIMESTAMP
        )
        """,

        // sessions(依赖 workspaces)
        """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
            jsonl_path TEXT NOT NULL,
            byte_offset INTEGER DEFAULT 0,
            last_line_number INTEGER DEFAULT 0,
            started_at TIMESTAMP NOT NULL,
            ended_at TIMESTAMP,
            state TEXT NOT NULL,
            model_used TEXT,
            is_imported INTEGER NOT NULL DEFAULT 0
        )
        """,
        "CREATE INDEX idx_sessions_workspace ON sessions(workspace_id)",
        "CREATE INDEX idx_sessions_state ON sessions(state) WHERE state IN ('live','idle')",

        // tasks(依赖 workspaces)
        """
        CREATE TABLE tasks (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL REFERENCES workspaces(id),
            title TEXT NOT NULL,
            intent TEXT,
            status TEXT NOT NULL,
            created_at TIMESTAMP NOT NULL,
            updated_at TIMESTAMP NOT NULL,
            completed_at TIMESTAMP
        )
        """,
        "CREATE INDEX idx_tasks_workspace_status ON tasks(workspace_id, status)",

        // task_sessions(join,依赖 tasks + sessions)
        """
        CREATE TABLE task_sessions (
            task_id TEXT REFERENCES tasks(id) ON DELETE CASCADE,
            session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
            attached_at TIMESTAMP NOT NULL,
            PRIMARY KEY (task_id, session_id)
        )
        """,

        // events(依赖 sessions)
        """
        CREATE TABLE events (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            type TEXT NOT NULL,
            category TEXT,
            tool_name TEXT,
            tool_use_id TEXT,
            paired_event_id TEXT,
            timestamp TIMESTAMP NOT NULL,
            line_number INTEGER NOT NULL,
            block_index INTEGER DEFAULT 0,
            summary TEXT NOT NULL,
            raw_payload_json TEXT,
            byte_offset_in_jsonl INTEGER
        )
        """,
        "CREATE INDEX idx_events_session_seq ON events(session_id, line_number, block_index)",
        "CREATE INDEX idx_events_tool_use_id ON events(tool_use_id) WHERE tool_use_id IS NOT NULL",
        "CREATE INDEX idx_events_type ON events(session_id, type)",

        // budgets(依赖 tasks)
        """
        CREATE TABLE budgets (
            task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
            max_input_tokens INTEGER,
            max_output_tokens INTEGER,
            max_cost_usd REAL,
            max_wall_seconds INTEGER,
            used_input_tokens INTEGER DEFAULT 0,
            used_output_tokens INTEGER DEFAULT 0,
            used_cost_usd REAL DEFAULT 0,
            used_wall_seconds INTEGER DEFAULT 0,
            state TEXT DEFAULT 'normal',
            updated_at TIMESTAMP NOT NULL
        )
        """,

        // plans(依赖 tasks)
        """
        CREATE TABLE plans (
            id TEXT PRIMARY KEY,
            task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
            source TEXT NOT NULL,
            steps_json TEXT NOT NULL,
            markdown_raw TEXT,
            updated_at TIMESTAMP NOT NULL
        )
        """,
        "CREATE INDEX idx_plans_task ON plans(task_id, updated_at DESC)",

        // layout_states(依赖 workspaces)
        """
        CREATE TABLE layout_states (
            workspace_id TEXT PRIMARY KEY REFERENCES workspaces(id) ON DELETE CASCADE,
            layout_json TEXT NOT NULL,
            updated_at TIMESTAMP NOT NULL
        )
        """,

        // approvals(v1.1,FK 不 CASCADE)
        """
        CREATE TABLE approvals (
            id TEXT PRIMARY KEY,
            session_id TEXT REFERENCES sessions(id),
            tool_name TEXT NOT NULL,
            tool_input_json TEXT NOT NULL,
            decision TEXT NOT NULL,
            decided_by TEXT NOT NULL,
            decided_at TIMESTAMP NOT NULL,
            reason TEXT
        )
        """,

        // settings(无 FK)
        """
        CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value_json TEXT NOT NULL,
            updated_at TIMESTAMP NOT NULL
        )
        """,

        // schema_versions(无 FK,migrator 填)
        """
        CREATE TABLE schema_versions (
            version INTEGER PRIMARY KEY,
            applied_at TIMESTAMP NOT NULL,
            description TEXT
        )
        """,
    ]
}
