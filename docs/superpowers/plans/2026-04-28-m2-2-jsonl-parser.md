# M2.2 实施计划:JSONLParser + 12 Event 映射 + tool_use↔result 配对

> **For agentic workers:** 本 plan 给 Claude 主导执行。用户 T11 做最终肉眼验收(跑一个 fixture + 瞄一眼 Event 列表)。步骤用 checkbox 跟踪。

**Goal:** 把 M2.1 watcher 发出的 raw JSONL 行字符串**解析**成领域模型 `CairnCore.Event` 列表 + 维护 **tool_use ↔ tool_result 的配对关系**。实现 spec §4.3 的 12 种 JSONL type 映射表 + spec §4.4 的 inflight 配对逻辑。**不做**:写入 SQLite events 表(M2.3 EventIngestor 干这个),不接 UI(M2.4),不改 session 生命周期状态(M2.6)。

**Architecture:** CairnClaude 新增 `Parser/` 子目录,按职责拆:

- `JSONLEntry`:JSONL 一行的 Codable 包装(对应文件里一行 JSON 对象的 **表层** schema,`type` + 通用元数据 + `message` 或子 type 特定字段)。因为 `user/assistant` 的 `message.content` 是异构(str/list、list 里 type text/thinking/tool_use/tool_result 混合),用手写 Decodable 或 `JSONSerialization` 解析再按类型派发
- `JSONLParser`:**纯函数** `parse(line:, sessionId:, lineNumber:, byteOffset:) -> [Event]`。单行可能产生 0-N 个 Event(e.g. `assistant` 一行可能同时有 text + thinking + tool_use + api_usage → 4 个 Event)
- `ToolPairingTracker`:**actor** 维护 inflight `[toolUseId: Event.id]` 字典。`observe(event)` 入口:
  - `.toolUse` 到达 → 记录
  - `.toolResult` 到达 → 查表拿 use 的 Event.id → 设 `pairedEventId` 指回
  - 重启后重建:本 milestone 只提供 `restore(from: [Event])` API,**不做 DB 查询**(那是 M2.3)
- fixtures 目录:10 个真实 JSONL 样本(从本机 `~/.claude/projects/` 裁剪),每个覆盖一个映射路径

M2.1 watcher 不知道 parser 存在;parser 也不管 watcher — 两者 M2.3 ingestor 里接上。本 milestone 交付就是"能解析一行 JSONL 得到一批 Event"。

**Tech Stack:**
- Swift `JSONDecoder` 主体 + 少量 `JSONSerialization` 处理异构 content
- Swift `actor` + `Dictionary` 管 inflight
- `CairnCore.Event` / `EventType` / `ToolCategory`(M1.1 就位,不改)
- Fixture 走真实 JSONL 片段 + XCTest

**Claude 耗时**:约 180-240 分钟。
**用户耗时**:约 10 分钟(T11 看一个 fixture 解析输出)。

---

## 任务归属一览

| Task | 谁做 | 依赖 |
|---|---|---|
| T1. Fixture 文件收集(10 个真实 JSONL 片段) | Claude | — |
| T2. `JSONLEntry` Codable 结构 + 异构 content 解析 | Claude | T1 |
| T3. `JSONLParser` — user entry → `user_message` 或 `tool_result` | Claude | T2 |
| T4. `JSONLParser` — assistant entry → `text`/`thinking`/`tool_use` + `api_usage` | Claude | T2 |
| T5. `JSONLParser` — system / custom-title / 忽略类(progress / attachment / file-history-snapshot / last-prompt / permission-mode / queue-operation / agent-name / tag) | Claude | T2 |
| T6. `JSONLParser` — 派生事件:`parentUuid == nil && !firstLine` → `compact_boundary`;`is_error: true` → `error` | Claude | T3,T4 |
| T7. `ToolPairingTracker` actor + `restore(from:)` | Claude | T3,T4 |
| T8. 10 fixture 测试(对每个 fixture 断言 parse 出的 Event 数量 + 关键字段) | Claude | T3-T7 |
| T9. Parser smoke 性能测试(1000 行 < 100ms) | Claude | T3-T6 |
| T10. scaffoldVersion `0.6.0-m2.1` → `0.7.0-m2.2` | Claude | — |
| T11. build + 全测试 + 真实 session JSONL 喂 parser 自检 | Claude | T1-T10 |
| T12. 用户验收(跑一个 fixture 看输出) | **用户** | T11 |

---

## 文件结构规划

**新建**:

```
Sources/CairnClaude/Parser/
├── JSONLEntry.swift             (T2 表层 Codable + content 异构解析)
├── JSONLParser.swift            (T3-T6 主入口 + 派生事件)
└── ToolPairingTracker.swift     (T7 actor)

Tests/CairnClaudeTests/Parser/
├── JSONLParserTests.swift       (T8 + T9)
├── ToolPairingTrackerTests.swift
└── fixtures/
    ├── user-text.jsonl                  (user role=user content=str)
    ├── user-tool-result.jsonl           (user role=user content=[tool_result])
    ├── assistant-text.jsonl             (assistant content=[text])
    ├── assistant-thinking.jsonl         (assistant content=[thinking])
    ├── assistant-tool-use.jsonl         (assistant content=[tool_use])
    ├── assistant-mixed.jsonl            (content=[thinking, text, tool_use])
    ├── system-with-cwd.jsonl            (metadata-only entry)
    ├── compact-boundary.jsonl           (parentUuid==null 非首行)
    ├── error-flag.jsonl                 (is_error: true)
    └── ignored-types.jsonl              (progress / attachment / file-history-snapshot / permission-mode / last-prompt 各一行)
```

fixture 内容**来自本机** `~/.claude/projects/-Users-sorain-xiaomi-projects-AICoding-cairn/*.jsonl` 的裁剪样本,长 text/content 截断到 80 字节保留可读。

**修改**:
- `Sources/CairnCore/CairnCore.swift`: scaffoldVersion bump(T10)
- `Tests/CairnCoreTests/CairnCoreTests.swift`: 断言字符串改 m2.2
- `Tests/CairnStorageTests/CairnStorageTests.swift`: 同上

---

## 设计决策(pinned)

| # | 决策 | 理由 |
|---|---|---|
| 1 | **Parser 无状态纯函数**(单行 JSON → `[Event]`) | 便于测试、可重入、并发友好;配对状态下沉到独立 actor |
| 2 | 单行可 yield 0-N 个 Event(mixed content) | spec §4.3 明示:assistant 一行的 content 是 array,每个 block 一个 Event |
| 3 | **block 顺序用 `blockIndex`**(0-based)作为 secondary 排序键 | Event 模型已有此字段(spec §2.6);UI 按 (lineNumber, blockIndex) 时间顺 |
| 4 | `JSONLEntry` 只解表层 + `message`,**深层 content list 按需懒解析** | 真实 schema 异构(str vs list,list 里多 type),全 Codable 复杂且性能差 |
| 5 | 异构 content 用 `JSONSerialization` 当 `[String: Any]` 手解析 | 够快,不依赖第三方;content block schema 由 Anthropic 定义,字段名稳定 |
| 6 | `api_usage` 作为**独立** Event 从 assistant 派生 | spec §4.3 "附带 `.api_usage`";UI 可独立展示成本/token 面板 |
| 7 | `api_usage.summary` 填 `"in=X out=Y cache=Z"` 人类可读,`rawPayloadJson` 留完整 usage 对象 | summary 用于 Timeline 一行摘要;原始 JSON 给 M3.x Budget 精确累加 |
| 8 | `compact_boundary` 派生条件:**非首行** 且 `parentUuid == null` | spec §4.3;首行 parentUuid 通常就是 null,不能误派生 |
| 9 | `.error` 派生条件:`is_error: true`(tool_result 或 assistant 子 block)→ **额外**发一个 error Event,**同时**保留原类型 | spec §4.3;Timeline 可以同时高亮"工具 X 返回错误"+"失败结果内容" |
| 10 | **忽略类型**(progress / attachment / file-history-snapshot / permission-mode / last-prompt / queue-operation / agent-name / tag / custom-title)返回空数组 | spec §4.3 的修订表;metadata 提取留 M2.6(Session 元数据)/ M3.x(Task.title 来自 custom-title) |
| 11 | `system` entry 返回空数组(不进 timeline),但**保留** cwd 解析钩子给 M2.6 | spec §4.3;cwd 是 workspace 反推的权威来源(probe Q1) |
| 12 | `ToolPairingTracker` 只管 in-memory inflight;**不查 DB** | 范围控制;DB 重建在 M2.3 接入 ingestor 时加 |
| 13 | Parser **不 mutate `Event.id`** — 每次 parse 都新 UUID | 同一行再次 parse 得到不同 ids,**在 M2.3 ingestor 用 `(sessionId, lineNumber, blockIndex)` 做 upsert 去重**(unique 约束,见 schema);本 milestone 不关心 idempotent |
| 14 | 错误行(malformed JSON / 未知 schema / decode 抛错)→ **返回空数组**,stderr 打 warning,不抛 | watcher 给的就是 raw 行,容错不崩;M2.7 打磨时收敛 warning |
| 15 | Parser 通用元数据提取:`timestamp` / `parentUuid` / `uuid`(Claude 给的 entry uuid,不等于 Event.id) | parentUuid 给 compact_boundary 用;entry uuid 存在 raw payload 不单独字段 |
| 16 | `toolUseId` 从 `content[i].id`(tool_use 的 id 字段)提取 | Anthropic schema |
| 17 | `summary` 生成策略:text 取前 80 字符;tool_use 取 `"{toolName}({firstArg})"`;tool_result 取前 80 字符 | UI 一行摘要好看即可,详情在 rawPayloadJson |
| 18 | **fixture 不含敏感信息**(用户 prompt / 路径),需要时替换为占位 | 公共仓可见 |
| 19 | 性能 smoke:1000 行混合 fixture,`measure {}` 块内 parse 单遍应 < 100ms | spec §8.5 M2.3 有 1000 行 500ms 要求;parser 层先定更严目标,留余量给 ingestor |
| 20 | `JSONLParser` 暴露 `parse` 静态方法(纯函数);不提供 actor / stream 接口 | M2.3 ingestor 会用 AsyncStream 串起 watcher + parser + pairing + dao |
| 21 | **tracker.observe 的 pairedEventId 指向 parser 当前生成的 UUID**(非 DB stable id) | parser 每次 parse 同一行生成新 UUID。M2.3 ingestor 的正确顺序**必须是**:① 先 `SessionDAO+EventDAO.upsert(event)` 按 `(sessionId, lineNumber, blockIndex)` 唯一约束换回 DB stable id,覆盖 `event.id`;② 再 `tracker.observe(events)`。否则 tool_result.paired_event_id 会指向不存在的 id。events 表 `paired_event_id` 无 FK(schema 故意如此),不会立即崩,但 UI 关联会失败。M2.2 plan **写入 Known limitations**,M2.3 必须实现此顺序 |

---

## 风险清单

| # | 风险 | 缓解 |
|---|---|---|
| 1 | `message.content` schema 未来变更(Anthropic 加新 block type) | 未知 block type → 跳过 + stderr warning,parser 不崩;spec §4.3 表可持续修订 |
| 2 | `is_error` 可能出现在多层(tool_result / assistant block / 顶层) | parser 统一在每个 block 解析后检查,不假定层级 |
| 3 | `timestamp` 缺失(某些 metadata 类 entry 没有)| 没 timestamp 的 entry 本就在忽略集;有用的 entry(user/assistant/system)实测都有 |
| 4 | parentUuid 是 string 还是 UUID? | 实测是 string(可能 UUID 格式,可能 "session-init" 之类 fallback);当 string 处理,非 null 即可 |
| 5 | content list 里有 tool_use 和 text 混合时 block 顺序 | 按 array index 分配 blockIndex;spec §2.6 定义 lineNumber + blockIndex 为主排序键 |
| 6 | `usage` 出现在历史 entry 但 Event 已生成后才发现 | 一行 assistant 一次性 parse 完 text/thinking/tool_use + usage,单行内顺序由 parser 保证 |
| 7 | Fixture 包含敏感信息 | 手工 sanitize,替换 user prompt 为 `"example prompt"`,替换路径为 `/tmp/example` |
| 8 | `ToolPairingTracker` 的 inflight dict 无界增长(未配对的 use 永远留着) | v1 接受;M2.6 session `.abandoned` 判定会清理;现阶段单个 session 几百上千 tool_use 内存可忽略 |

---

## 对外 API 定义(T7 完成后固化)

```swift
// Sources/CairnClaude/Parser/JSONLParser.swift

public enum JSONLParser {
    /// 解析一行 JSONL → 0-N 个 Event。
    /// `isFirstLine`:JSONL 文件首行不派生 compact_boundary,即使 parentUuid==nil。
    public static func parse(
        line: String,
        sessionId: UUID,
        lineNumber: Int64,
        byteOffsetInJsonl: Int64? = nil,
        isFirstLine: Bool = false
    ) -> [Event]
}

// Sources/CairnClaude/Parser/ToolPairingTracker.swift

public actor ToolPairingTracker {
    public init()

    /// 观察一批 Event:若有 tool_use 记录 inflight,若有 tool_result 查表并回填
    /// 返回的 Event 数组是**已配对的版本**(tool_result 的 `pairedEventId` 已填)。
    public func observe(_ events: [Event]) -> [Event]

    /// 重启时用已从 DB 加载的 Event 列表重建 inflight(未配对的 tool_use)。
    public func restore(from existing: [Event])

    /// 诊断用。
    public func inflightCount() -> Int
}
```

M2.3 EventIngestor 的典型用法:

```swift
let parser = JSONLParser.self
let tracker = ToolPairingTracker()

for await event in watcher.events() {
    if case .lines(let sid, let lines, let lineNumberStart) = event {
        for (i, line) in lines.enumerated() {
            let lineNum = lineNumberStart + Int64(i)
            let events = parser.parse(line: line, sessionId: sid, lineNumber: lineNum)
            let paired = await tracker.observe(events)
            try await eventDao.batchInsert(paired, in: db)  // M2.3
        }
    }
}
```

---

## Tasks

### Task 1: Fixture 文件收集

**Files**:
- Create: `Tests/CairnClaudeTests/Parser/fixtures/*.jsonl`(10 个)

- [ ] **Step 1: 从本机真实 JSONL 裁剪 + sanitize**

挑选源文件:`~/.claude/projects/-Users-sorain-xiaomi-projects-AICoding-cairn/2626ca25-*.jsonl`。

用这个 shell + python 脚本生成 fixtures:

```bash
mkdir -p Tests/CairnClaudeTests/Parser/fixtures
python3 <<'PY'
import json, os
src = os.path.expanduser('~/.claude/projects/-Users-sorain-xiaomi-projects-AICoding-cairn/2626ca25-0515-4e42-9521-902aff636617.jsonl')
out_dir = 'Tests/CairnClaudeTests/Parser/fixtures'

def sanitize(s):
    # 用户 prompt 里可能的敏感信息,替换为占位
    if isinstance(s, str) and len(s) > 120:
        return s[:80] + '...'
    return s

def walk(obj, fn):
    if isinstance(obj, dict):
        return {k: walk(v, fn) for k, v in obj.items()}
    if isinstance(obj, list):
        return [walk(x, fn) for x in obj]
    return fn(obj)

entries = []
with open(src) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        entries.append(json.loads(line))

def find(pred):
    for e in entries:
        if pred(e): return e
    return None

def write_fixture(name, entry):
    sanitized = walk(entry, sanitize) if entry else None
    with open(f'{out_dir}/{name}', 'w') as f:
        if sanitized:
            f.write(json.dumps(sanitized) + '\n')

# 10 fixtures
write_fixture('user-text.jsonl',
    find(lambda e: e.get('type')=='user' and isinstance(e.get('message',{}).get('content'),str)))
write_fixture('user-tool-result.jsonl',
    find(lambda e: e.get('type')=='user' and isinstance(e.get('message',{}).get('content'),list)
         and any(c.get('type')=='tool_result' for c in e['message']['content'])))
write_fixture('assistant-text.jsonl',
    find(lambda e: e.get('type')=='assistant'
         and isinstance(e.get('message',{}).get('content'),list)
         and [c.get('type') for c in e['message']['content']] == ['text']))
write_fixture('assistant-thinking.jsonl',
    find(lambda e: e.get('type')=='assistant'
         and [c.get('type') for c in e.get('message',{}).get('content',[])] == ['thinking']))
write_fixture('assistant-tool-use.jsonl',
    find(lambda e: e.get('type')=='assistant'
         and [c.get('type') for c in e.get('message',{}).get('content',[])] == ['tool_use']))
# assistant-mixed 没有现成的(本 session 里 assistant 基本单 block),手造一条
assistant_tu = find(lambda e: e.get('type')=='assistant'
                    and [c.get('type') for c in e.get('message',{}).get('content',[])] == ['tool_use'])
if assistant_tu:
    mixed = json.loads(json.dumps(assistant_tu))
    thinking_block = {"type":"thinking","thinking":"let me think about this","signature":"abc"}
    text_block = {"type":"text","text":"okay here is the plan"}
    mixed['message']['content'] = [thinking_block, text_block] + mixed['message']['content']
    with open(f'{out_dir}/assistant-mixed.jsonl','w') as f:
        f.write(json.dumps(mixed) + '\n')

write_fixture('system-with-cwd.jsonl',
    find(lambda e: e.get('type')=='system' and e.get('cwd')))

# compact-boundary: 手造 parentUuid == None 的非首行 entry
user = find(lambda e: e.get('type')=='user' and isinstance(e.get('message',{}).get('content'),str))
if user:
    boundary = json.loads(json.dumps(user))
    boundary['parentUuid'] = None
    with open(f'{out_dir}/compact-boundary.jsonl','w') as f:
        f.write(json.dumps(boundary) + '\n')

# error-flag:手造 tool_result 含 is_error
tool_res = find(lambda e: e.get('type')=='user' and isinstance(e.get('message',{}).get('content'),list)
                and any(c.get('type')=='tool_result' for c in e['message']['content']))
if tool_res:
    err = json.loads(json.dumps(tool_res))
    for c in err['message']['content']:
        if c.get('type')=='tool_result':
            c['is_error'] = True
            break
    with open(f'{out_dir}/error-flag.jsonl','w') as f:
        f.write(json.dumps(err) + '\n')

# ignored-types:4 行各一个 type(progress 没在本 session 就手造)
ignored = []
for t in ['attachment','file-history-snapshot','permission-mode','last-prompt']:
    e = find(lambda x: x.get('type')==t)
    if e:
        ignored.append(walk(e, sanitize))
# 加一个手造的 progress
ignored.append({'type':'progress','sessionId':'abc','parentToolUseId':'xyz','stage':'running'})
with open(f'{out_dir}/ignored-types.jsonl','w') as f:
    for e in ignored:
        f.write(json.dumps(e) + '\n')

print('fixtures:')
for fn in sorted(os.listdir(out_dir)):
    size = os.path.getsize(f'{out_dir}/{fn}')
    print(f'  {fn}  {size}B')
PY
```

- [ ] **Step 2: 人工过一遍 fixtures,确保没敏感信息**

```bash
for f in Tests/CairnClaudeTests/Parser/fixtures/*.jsonl; do
    echo "=== $f ==="
    python3 -c "import json; [print(json.dumps(json.loads(l), ensure_ascii=False, indent=2)[:500]) for l in open('$f').read().strip().split(chr(10)) if l]"
done | head -200
```
如发现实际路径 / prompt 细节,手工改成占位(如 `/Users/sorain/...` → `/tmp/example`)。

- [ ] **Step 3: commit**

```bash
git add Tests/CairnClaudeTests/Parser/fixtures/
git commit -m "test(m2.2): JSONL parser fixtures (10 real-derived samples)"
```

---

### Task 2: JSONLEntry Codable + content 解析

**Files**:
- Create: `Sources/CairnClaude/Parser/JSONLEntry.swift`

**要点**:表层用 `Codable` 结构解出通用字段,`message.content` 保留为 `Any`(通过 `JSONSerialization`)方便 parser 按 type 分派。

- [ ] **Step 1: 实现**

```swift
// Sources/CairnClaude/Parser/JSONLEntry.swift
import Foundation

/// JSONL 一行的通用表层 schema(user / assistant / system / 其他)。
/// content 是异构的(str / list of mixed blocks),用原始 JSON `[String: Any]`
/// 表示,由 JSONLParser 按需拆。
public struct JSONLEntry {
    public let type: String
    public let parentUuid: String?
    public let timestamp: Date?
    public let sessionId: String?
    public let uuid: String?
    public let cwd: String?
    public let message: [String: Any]?
    /// 是否是 subagent sidechain(claude code 的子会话)
    public let isSidechain: Bool?
    /// 原始 JSON 对象,raw_payload 用
    public let rawJson: String

    public enum ParseError: Error {
        case invalidJSON
        case missingType
    }

    public static func parse(_ line: String) throws -> JSONLEntry {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.invalidJSON
        }
        guard let type = obj["type"] as? String else {
            throw ParseError.missingType
        }
        let timestamp: Date? = {
            guard let s = obj["timestamp"] as? String else { return nil }
            // 真实 Claude JSONL timestamp 两种格式并存:
            //   "2024-01-02T03:04:05.123Z"(含毫秒)
            //   "2024-01-02T03:04:05Z"(不含)
            // 只配一个 formatter 会漏解其中一种,回落到另一种。
            if let d = ISO8601DateFormatter.withFractional.date(from: s) { return d }
            return ISO8601DateFormatter.basic.date(from: s)
        }()
        return JSONLEntry(
            type: type,
            parentUuid: obj["parentUuid"] as? String,
            timestamp: timestamp,
            sessionId: obj["sessionId"] as? String,
            uuid: obj["uuid"] as? String,
            cwd: obj["cwd"] as? String,
            message: obj["message"] as? [String: Any],
            isSidechain: obj["isSidechain"] as? Bool,
            rawJson: line
        )
    }
}

// 统一 ISO8601 解码器(两个,对应两种真实格式)
private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let basic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
```

- [ ] **Step 2: build verify**

```bash
swift build
```
期望:`Build complete!`

- [ ] **Step 3: commit**

```bash
git add Sources/CairnClaude/Parser/JSONLEntry.swift
git commit -m "feat(m2.2): JSONLEntry — generic JSONL line wrapper with heterogeneous content"
```

---

### Task 3: JSONLParser — user entry

**Files**:
- Create: `Sources/CairnClaude/Parser/JSONLParser.swift`
- Modify: `Tests/CairnClaudeTests/Parser/JSONLParserTests.swift`(T8 建)

- [ ] **Step 1: 实现 user 分支骨架**

```swift
// Sources/CairnClaude/Parser/JSONLParser.swift
import Foundation
import CairnCore

public enum JSONLParser {
    public static func parse(
        line: String,
        sessionId: UUID,
        lineNumber: Int64,
        byteOffsetInJsonl: Int64? = nil,
        isFirstLine: Bool = false
    ) -> [Event] {
        guard let entry = try? JSONLEntry.parse(line) else {
            FileHandle.standardError.write(Data(
                "[JSONLParser] malformed line #\(lineNumber): \(line.prefix(120))\n".utf8
            ))
            return []
        }
        let ts = entry.timestamp ?? Date()
        var events: [Event] = []

        switch entry.type {
        case "user":
            events = parseUser(entry, sessionId: sessionId, lineNumber: lineNumber, ts: ts)
        case "assistant":
            events = []  // T4
        case "system", "custom-title",
             "progress", "attachment", "file-history-snapshot",
             "permission-mode", "last-prompt", "queue-operation",
             "agent-name", "tag":
            events = []  // 忽略类型:无 content 事件,但**仍走下面 compact 派生**
                        // —— spec §4.3 "parentUuid == null 非首行 → compact_boundary"
                        // 与 entry type 正交。attachment/system 有 parentUuid 字段,
                        // 刚 compact 后的那条 entry 无论什么 type 都应派生 boundary。
        default:
            FileHandle.standardError.write(Data(
                "[JSONLParser] unknown type '\(entry.type)' line #\(lineNumber)\n".utf8
            ))
            return []  // 未知 type 视为完全不处理,不派生 compact(避免垃圾数据乱派生)
        }

        // T6 派生事件
        if entry.parentUuid == nil && !isFirstLine {
            // compact_boundary
            events.append(Event(
                sessionId: sessionId,
                type: .compactBoundary,
                timestamp: ts,
                lineNumber: lineNumber,
                blockIndex: events.count,
                summary: "context compacted",
                rawPayloadJson: entry.rawJson,
                byteOffsetInJsonl: byteOffsetInJsonl
            ))
        }

        // 填充 byteOffset(通用)
        return events.map { e in
            var copy = e
            copy.byteOffsetInJsonl = byteOffsetInJsonl
            return copy
        }
    }

    // MARK: - user

    private static func parseUser(
        _ entry: JSONLEntry, sessionId: UUID, lineNumber: Int64, ts: Date
    ) -> [Event] {
        guard let msg = entry.message else { return [] }
        guard let content = msg["content"] else { return [] }

        // content 是 str → user_message
        if let s = content as? String {
            return [Event(
                sessionId: sessionId,
                type: .userMessage,
                timestamp: ts,
                lineNumber: lineNumber,
                blockIndex: 0,
                summary: summarize(text: s),
                rawPayloadJson: entry.rawJson
            )]
        }

        // content 是 list → tool_result × N(v1 只关心 tool_result;user role 的
        // list content 实测都是 tool_result 集合)
        guard let list = content as? [[String: Any]] else { return [] }
        var events: [Event] = []
        for (i, block) in list.enumerated() {
            guard let btype = block["type"] as? String else { continue }
            switch btype {
            case "tool_result":
                let toolUseId = block["tool_use_id"] as? String
                let resultContent = block["content"]
                let isError = (block["is_error"] as? Bool) ?? false
                let summary = summarize(toolResultContent: resultContent)
                events.append(Event(
                    sessionId: sessionId,
                    type: .toolResult,
                    toolUseId: toolUseId,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: summary,
                    rawPayloadJson: entry.rawJson
                ))
                if isError {
                    // T6 派生 .error
                    events.append(Event(
                        sessionId: sessionId,
                        type: .error,
                        toolUseId: toolUseId,
                        timestamp: ts,
                        lineNumber: lineNumber,
                        blockIndex: events.count,
                        summary: "tool_result reported error",
                        rawPayloadJson: entry.rawJson
                    ))
                }
            default:
                continue  // 未知 block type 忽略
            }
        }
        return events
    }

    // MARK: - summarize

    static func summarize(text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80)) + "…"
    }

    static func summarize(toolResultContent: Any?) -> String {
        if let s = toolResultContent as? String {
            return summarize(text: s)
        }
        if let list = toolResultContent as? [[String: Any]] {
            for b in list {
                if let t = b["text"] as? String { return summarize(text: t) }
            }
        }
        return "(tool result)"
    }
}
```

- [ ] **Step 2: build verify**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 3: commit(test 在 T8 统一写)**

```bash
git add Sources/CairnClaude/Parser/JSONLParser.swift
git commit -m "feat(m2.2): JSONLParser user entry mapping (user_message + tool_result)"
```

---

### Task 4: JSONLParser — assistant entry

**Files**:
- Modify: `Sources/CairnClaude/Parser/JSONLParser.swift`

- [ ] **Step 1: 加 `parseAssistant` 并在 switch 里接**

```swift
        case "assistant":
            events = parseAssistant(entry, sessionId: sessionId, lineNumber: lineNumber, ts: ts)
```

```swift
    // MARK: - assistant

    private static func parseAssistant(
        _ entry: JSONLEntry, sessionId: UUID, lineNumber: Int64, ts: Date
    ) -> [Event] {
        guard let msg = entry.message,
              let list = msg["content"] as? [[String: Any]] else { return [] }
        var events: [Event] = []
        for (i, block) in list.enumerated() {
            guard let btype = block["type"] as? String else { continue }
            switch btype {
            case "text":
                let text = block["text"] as? String ?? ""
                events.append(Event(
                    sessionId: sessionId,
                    type: .assistantText,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: summarize(text: text),
                    rawPayloadJson: entry.rawJson
                ))
            case "thinking":
                let text = block["thinking"] as? String ?? ""
                events.append(Event(
                    sessionId: sessionId,
                    type: .assistantThinking,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: summarize(text: text),
                    rawPayloadJson: entry.rawJson
                ))
            case "tool_use":
                let toolName = block["name"] as? String ?? "unknown"
                let toolUseId = block["id"] as? String
                let inputSummary = summarize(toolUseInput: block["input"], toolName: toolName)
                events.append(Event(
                    sessionId: sessionId,
                    type: .toolUse,
                    category: ToolCategory.from(toolName: toolName),
                    toolName: toolName,
                    toolUseId: toolUseId,
                    timestamp: ts,
                    lineNumber: lineNumber,
                    blockIndex: i,
                    summary: inputSummary,
                    rawPayloadJson: entry.rawJson
                ))
                if (block["is_error"] as? Bool) == true {
                    events.append(Event(
                        sessionId: sessionId,
                        type: .error,
                        toolUseId: toolUseId,
                        timestamp: ts,
                        lineNumber: lineNumber,
                        blockIndex: events.count,
                        summary: "tool_use reported error",
                        rawPayloadJson: entry.rawJson
                    ))
                }
            default:
                continue
            }
        }

        // 附带 api_usage(如果 message.usage 存在)
        if let usage = msg["usage"] as? [String: Any] {
            let inputTok = (usage["input_tokens"] as? Int) ?? 0
            let outputTok = (usage["output_tokens"] as? Int) ?? 0
            let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0
            let summary = "in=\(inputTok) out=\(outputTok) cache=\(cacheRead)"
            events.append(Event(
                sessionId: sessionId,
                type: .apiUsage,
                timestamp: ts,
                lineNumber: lineNumber,
                blockIndex: events.count,
                summary: summary,
                rawPayloadJson: entry.rawJson
            ))
        }

        return events
    }

    static func summarize(toolUseInput: Any?, toolName: String) -> String {
        // 简化:找第一个 string-ish value 作为参数概览
        if let dict = toolUseInput as? [String: Any] {
            for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
                if let s = v as? String, !s.isEmpty {
                    return "\(toolName)(\(k)=\(summarize(text: s)))"
                }
            }
        }
        return "\(toolName)()"
    }
```

- [ ] **Step 2: build**

```bash
swift build 2>&1 | grep -E "error:|Build complete"
```

- [ ] **Step 3: commit**

```bash
git add Sources/CairnClaude/Parser/JSONLParser.swift
git commit -m "feat(m2.2): JSONLParser assistant entry (text/thinking/tool_use + api_usage)"
```

---

### Task 5: JSONLParser — 忽略类型 + custom-title(已在 T3 switch 里)

T3 已在 switch 里把忽略类型列出。本 Task 确认完整性:

- [ ] **Step 1: 在 `parse()` 的 switch 里确认以下 types 返回 []**

- `attachment`、`system`、`custom-title`、`progress`、`file-history-snapshot`、`last-prompt`、`permission-mode`、`queue-operation`、`agent-name`、`tag`

T3 已覆盖,本 Task 无代码改动。是一个"review 确认"的 step。

- [ ] **Step 2: 跑 build 确认无 regression**

```bash
swift build
```

- [ ] **Step 3: 不单独 commit**(已并入 T3 的 switch)

---

### Task 6: 派生事件(compact_boundary / error)

T3 和 T4 已在各自分支里包含 `.error` 派生。compact_boundary 在 `parse()` 顶层派生(T3 代码里已写)。本 Task 确认:

- [ ] **Step 1: review T3 代码里的 compact_boundary 逻辑**

要求:
- `entry.parentUuid == nil`
- `isFirstLine == false`
- 无论 entry type,只要满足以上两条就派生

- [ ] **Step 2: review T3/T4 代码里的 .error 派生**

要求:
- tool_result 含 `is_error: true` → 在 tool_result Event 之后追加 .error Event
- tool_use 含 `is_error: true` → 同上

已在前两个 Task 实现。

- [ ] **Step 3: 不单独 commit**

---

### Task 7: ToolPairingTracker

**Files**:
- Create: `Sources/CairnClaude/Parser/ToolPairingTracker.swift`
- Create: `Tests/CairnClaudeTests/Parser/ToolPairingTrackerTests.swift`

- [ ] **Step 1: 实现**

```swift
// Sources/CairnClaude/Parser/ToolPairingTracker.swift
import Foundation
import CairnCore

/// 维护 tool_use ↔ tool_result 的 in-memory 配对关系。
/// 重启后 DB 重建由 M2.3 EventIngestor 调用 `restore(from:)` 完成。
///
/// **⚠️ id 稳定性约束**:observe 里 inflight 存的是**传入 event 的 id**。
/// 如果 caller 先做 DB upsert 把 Event.id 替换成 stable 值再调 observe,
/// 配对后的 pairedEventId 才能指向 DB 里真实存在的 row。M2.3 EventIngestor
/// **必须**按此顺序调度,否则 tool_result.paired_event_id 指向不存在的 id。
/// M2.2 范围只保证"同一 parser 流里 tool_use→tool_result id 一致"。
public actor ToolPairingTracker {
    private var inflight: [String: UUID] = [:]  // toolUseId → tool_use Event.id

    public init() {}

    /// 处理一批 Event:tool_use 入 inflight;tool_result 出 inflight + 填 pairedEventId。
    /// 返回修正后的 Event 数组(tool_result 的 pairedEventId 已填)。
    public func observe(_ events: [Event]) -> [Event] {
        return events.map { event in
            switch event.type {
            case .toolUse:
                if let tid = event.toolUseId {
                    inflight[tid] = event.id
                }
                return event
            case .toolResult:
                guard let tid = event.toolUseId,
                      let useId = inflight.removeValue(forKey: tid) else {
                    return event
                }
                var paired = event
                paired.pairedEventId = useId
                return paired
            default:
                return event
            }
        }
    }

    /// 重建 inflight:从已 persisted 的 Event 列表找出未配对的 tool_use。
    /// 规则:tool_use 若对应 tool_use_id 没有一条 tool_result → 仍 inflight。
    public func restore(from existing: [Event]) {
        inflight.removeAll()
        var useEvents: [String: UUID] = [:]
        var resultUseIds: Set<String> = []
        for e in existing {
            guard let tid = e.toolUseId else { continue }
            switch e.type {
            case .toolUse: useEvents[tid] = e.id
            case .toolResult: resultUseIds.insert(tid)
            default: break
            }
        }
        for (tid, useId) in useEvents where !resultUseIds.contains(tid) {
            inflight[tid] = useId
        }
    }

    public func inflightCount() -> Int { inflight.count }
}
```

- [ ] **Step 2: 写测试**

```swift
// Tests/CairnClaudeTests/Parser/ToolPairingTrackerTests.swift
import XCTest
import CairnCore
@testable import CairnClaude

final class ToolPairingTrackerTests: XCTestCase {
    func test_pairsUseThenResult() async throws {
        let tracker = ToolPairingTracker()
        let sid = UUID()
        let use = Event(
            sessionId: sid, type: .toolUse,
            toolName: "Bash", toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 1, summary: "Bash"
        )
        let result = Event(
            sessionId: sid, type: .toolResult,
            toolUseId: "tu_1",
            timestamp: Date(), lineNumber: 2, summary: "ok"
        )
        _ = await tracker.observe([use])
        XCTAssertEqual(await tracker.inflightCount(), 1)
        let paired = await tracker.observe([result])
        XCTAssertEqual(paired.first?.pairedEventId, use.id)
        XCTAssertEqual(await tracker.inflightCount(), 0)
    }

    func test_unpairedResultPassesThrough() async throws {
        let tracker = ToolPairingTracker()
        let orphan = Event(
            sessionId: UUID(), type: .toolResult,
            toolUseId: "tu_missing",
            timestamp: Date(), lineNumber: 1, summary: "orphan"
        )
        let out = await tracker.observe([orphan])
        XCTAssertNil(out.first?.pairedEventId)
    }

    func test_restoreFromExisting() async throws {
        let tracker = ToolPairingTracker()
        let sid = UUID()
        let use1 = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_1",
                         timestamp: Date(), lineNumber: 1, summary: "")
        let use2 = Event(sessionId: sid, type: .toolUse, toolUseId: "tu_2",
                         timestamp: Date(), lineNumber: 2, summary: "")
        let res2 = Event(sessionId: sid, type: .toolResult, toolUseId: "tu_2",
                         timestamp: Date(), lineNumber: 3, summary: "")
        // use1 未配对,use2 已配对
        await tracker.restore(from: [use1, use2, res2])
        XCTAssertEqual(await tracker.inflightCount(), 1)
    }
}
```

- [ ] **Step 3: 跑测试**

```bash
swift test --filter ToolPairingTrackerTests 2>&1 | grep -E "Executed|fail"
```
期望:3 tests pass。

- [ ] **Step 4: commit**

```bash
git add Sources/CairnClaude/Parser/ToolPairingTracker.swift Tests/CairnClaudeTests/Parser/ToolPairingTrackerTests.swift
git commit -m "feat(m2.2): ToolPairingTracker — actor for tool_use↔result inflight"
```

---

### Task 8: 10 fixture 测试

**Files**:
- Create: `Tests/CairnClaudeTests/Parser/JSONLParserTests.swift`

- [ ] **Step 1: 写测试**

```swift
// Tests/CairnClaudeTests/Parser/JSONLParserTests.swift
import XCTest
import CairnCore
@testable import CairnClaude

final class JSONLParserTests: XCTestCase {
    private let sid = UUID()

    private func loadFixture(_ name: String) throws -> [String] {
        // ⚠️ subdirectory 必须含完整相对路径。Package.swift 里
        // `.copy("Parser/fixtures")` 保留路径,bundle 内资源在 Parser/fixtures/
        // 下,不是扁平的 fixtures/。只写 "fixtures" 会 nil!
        let url = Bundle.module.url(
            forResource: name, withExtension: "jsonl",
            subdirectory: "Parser/fixtures"
        )!
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func parseFirst(_ fixture: String, lineNumber: Int64 = 1, isFirstLine: Bool = true) throws -> [Event] {
        let lines = try loadFixture(fixture)
        return JSONLParser.parse(
            line: lines[0], sessionId: sid,
            lineNumber: lineNumber, isFirstLine: isFirstLine
        )
    }

    // MARK: - user

    func test_userText_mapsToUserMessage() throws {
        let events = try parseFirst("user-text")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .userMessage)
        XCTAssertFalse(events[0].summary.isEmpty)
    }

    func test_userToolResult_mapsToToolResult() throws {
        let events = try parseFirst("user-tool-result")
        XCTAssertTrue(events.contains { $0.type == .toolResult })
        XCTAssertNotNil(events.first { $0.type == .toolResult }?.toolUseId)
    }

    // MARK: - assistant

    func test_assistantText() throws {
        let events = try parseFirst("assistant-text")
        // 严格 count:text(block 0)+ api_usage(派生) = 2
        XCTAssertEqual(events.count, 2, "got types \(events.map(\.type))")
        XCTAssertEqual(events[0].type, .assistantText)
        XCTAssertEqual(events[0].blockIndex, 0)
        XCTAssertEqual(events[1].type, .apiUsage)
        XCTAssertEqual(events[1].blockIndex, 1)
    }

    func test_assistantThinking() throws {
        let events = try parseFirst("assistant-thinking")
        XCTAssertTrue(events.contains { $0.type == .assistantThinking })
    }

    func test_assistantToolUse() throws {
        let events = try parseFirst("assistant-tool-use")
        let tu = events.first { $0.type == .toolUse }
        XCTAssertNotNil(tu)
        XCTAssertNotNil(tu?.toolName)
        XCTAssertNotNil(tu?.toolUseId)
    }

    func test_assistantMixed_multipleBlocks() throws {
        let events = try parseFirst("assistant-mixed")
        // mixed fixture 有 thinking + text + tool_use,共 3 个 content block + api_usage
        let types = events.map(\.type)
        XCTAssertTrue(types.contains(.assistantThinking))
        XCTAssertTrue(types.contains(.assistantText))
        XCTAssertTrue(types.contains(.toolUse))
        XCTAssertTrue(types.contains(.apiUsage))
        // blockIndex 单调递增
        for i in 1..<events.count {
            XCTAssertGreaterThanOrEqual(events[i].blockIndex, events[i-1].blockIndex)
        }
    }

    // MARK: - 忽略类型

    func test_systemEntry_returnsEmpty() throws {
        let events = try parseFirst("system-with-cwd")
        XCTAssertTrue(events.isEmpty)
    }

    func test_ignoredTypes_allReturnEmpty() throws {
        let lines = try loadFixture("ignored-types")
        for line in lines {
            let events = JSONLParser.parse(
                line: line, sessionId: sid,
                lineNumber: 1, isFirstLine: true
            )
            XCTAssertTrue(events.isEmpty, "expected empty for ignored type, got \(events)")
        }
    }

    // MARK: - 派生事件

    func test_compactBoundary_derivesOnNullParent() throws {
        let events = try parseFirst("compact-boundary", lineNumber: 5, isFirstLine: false)
        // user entry 的 user_message + compact_boundary 派生
        XCTAssertTrue(events.contains { $0.type == .compactBoundary })
    }

    func test_compactBoundary_skippedOnFirstLine() throws {
        let events = try parseFirst("compact-boundary", lineNumber: 1, isFirstLine: true)
        XCTAssertFalse(events.contains { $0.type == .compactBoundary })
    }

    func test_errorFlag_derivesErrorEvent() throws {
        let events = try parseFirst("error-flag")
        XCTAssertTrue(events.contains { $0.type == .error })
    }

    // MARK: - 容错

    func test_malformedJson_returnsEmptyWithoutCrash() {
        let events = JSONLParser.parse(
            line: "{broken json",
            sessionId: sid, lineNumber: 1, isFirstLine: true
        )
        XCTAssertTrue(events.isEmpty)
    }
}
```

- [ ] **Step 2: 给 test target 加 resources**

编辑 `Package.swift` 的 CairnClaudeTests target 让它 bundle fixtures 文件:

```swift
.testTarget(
    name: "CairnClaudeTests",
    dependencies: ["CairnClaude"],
    resources: [.copy("Parser/fixtures")]
),
```

- [ ] **Step 3: 跑测试**

```bash
swift test --filter JSONLParserTests 2>&1 | grep -E "Executed|fail|error:"
```
期望:12 tests pass(含 malformed + 各 fixture 覆盖)。

- [ ] **Step 4: 如有 fixture 实际 schema 和 parser 期望不符,按 fixture 实情调 parser 或 fixture(fixture 是真实样本,通常改 parser 的边界)**

- [ ] **Step 5: commit**

```bash
git add Package.swift Tests/CairnClaudeTests/Parser/JSONLParserTests.swift
git commit -m "test(m2.2): 12 JSONLParser tests against 10 real-derived fixtures"
```

---

### Task 9: 性能 smoke

**Files**:
- Modify: `Tests/CairnClaudeTests/Parser/JSONLParserTests.swift`

- [ ] **Step 1: 加一个 measure block**

```swift
    /// 性能 smoke:1000 行混合 fixture,单线程 parse 应 < 100ms。
    /// spec §8.5 M2.3 有 "1000 行 < 500ms" 要求,parser 层定更严目标留余量。
    func test_parse1000Lines_underOneHundredMs() throws {
        // 拼一个长的 fixture:每个 fixture 重复 ~100 次到 1000 行
        let fixtures = ["user-text", "assistant-text", "assistant-tool-use",
                        "user-tool-result", "system-with-cwd"]
        var lines: [String] = []
        for name in fixtures {
            let fx = try loadFixture(name)
            for _ in 0..<(1000 / fixtures.count) {
                lines.append(contentsOf: fx)
            }
        }
        while lines.count > 1000 { lines.removeLast() }
        XCTAssertEqual(lines.count, 1000)

        measure {
            var count = 0
            for (i, line) in lines.enumerated() {
                count += JSONLParser.parse(
                    line: line, sessionId: sid,
                    lineNumber: Int64(i + 1), isFirstLine: i == 0
                ).count
            }
            XCTAssertGreaterThan(count, 0)
        }
    }
```

XCTest `measure` 默认跑 10 iteration 取平均,但不 assert 时长;只是性能 baseline。我们 assert 是**单 iteration 结束后**单轮时长 < 100ms 用 DispatchTime 手动测:

```swift
    func test_parse1000Lines_underOneHundredMs_hardAssert() throws {
        let fixtures = ["user-text", "assistant-text", "assistant-tool-use",
                        "user-tool-result", "system-with-cwd"]
        var lines: [String] = []
        for name in fixtures {
            let fx = try loadFixture(name)
            for _ in 0..<(1000 / fixtures.count) {
                lines.append(contentsOf: fx)
            }
        }
        while lines.count > 1000 { lines.removeLast() }

        let start = DispatchTime.now()
        var total = 0
        for (i, line) in lines.enumerated() {
            total += JSONLParser.parse(
                line: line, sessionId: sid,
                lineNumber: Int64(i + 1), isFirstLine: i == 0
            ).count
        }
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000
        XCTAssertLessThan(elapsedMs, 300, "1000 行 parse \(elapsedMs)ms,超过 300ms 上限")
        XCTAssertGreaterThan(total, 0)
    }
```

300ms 上限给 CI 留余量(本地应明显更快)。

- [ ] **Step 2: 跑**

```bash
swift test --filter JSONLParserTests 2>&1 | grep -E "Executed|fail"
```

- [ ] **Step 3: commit**

```bash
git add Tests/CairnClaudeTests/Parser/JSONLParserTests.swift
git commit -m "test(m2.2): JSONLParser 1000-line smoke perf (< 300ms)"
```

---

### Task 10: scaffoldVersion bump

**Files**:
- `Sources/CairnCore/CairnCore.swift`
- `Tests/CairnCoreTests/CairnCoreTests.swift`
- `Tests/CairnStorageTests/CairnStorageTests.swift`

- [ ] **Step 1: 全文替换 `0.6.0-m2.1` → `0.7.0-m2.2`** 和相关断言

- [ ] **Step 2: build + test**

```bash
swift build && swift test 2>&1 | grep "Executed"
```

- [ ] **Step 3: commit**

```bash
git add Sources/CairnCore/CairnCore.swift Tests/CairnCoreTests/CairnCoreTests.swift Tests/CairnStorageTests/CairnStorageTests.swift
git commit -m "chore(core): scaffoldVersion 0.6.0-m2.1 → 0.7.0-m2.2"
```

---

### Task 11: build + 真实 session 喂 parser 自检

**Files**:
- 无新建,创建临时 CLI 小脚本

- [ ] **Step 1: 全测试**

```bash
swift test 2>&1 | grep "Executed"
```
期望:≥ 143 + M2.2 新增(约 15 parser + 3 tracker)= ~161。

- [ ] **Step 2: 真实 JSONL 喂 parser**

写一个临时 swift 脚本 `/tmp/parse-real.swift`(或用 ExecutableTarget 临时加一个 sample-runner,完后删)。最简方式 — 加一个 CairnClaudeTests 测试方法,跑本机真实 session 上的 parse:

```swift
    /// 本地 smoke:真实 session JSONL 整份 parse 不崩 + 事件数合理。
    /// 这个测试只在开发机跑(文件路径硬编码)。如果路径不存在则 skip。
    func test_localRealSession_parses() throws {
        let path = "\(NSHomeDirectory())/.claude/projects/-Users-sorain-xiaomi-projects-AICoding-cairn/2626ca25-0515-4e42-9521-902aff636617.jsonl"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("real session file not present on this machine")
        }
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let lines = content.split(separator: "\n").map(String.init)
        var totalEvents = 0
        var byType: [EventType: Int] = [:]
        for (i, line) in lines.enumerated() {
            let events = JSONLParser.parse(
                line: line, sessionId: sid,
                lineNumber: Int64(i + 1), isFirstLine: i == 0
            )
            totalEvents += events.count
            for e in events {
                byType[e.type, default: 0] += 1
            }
        }
        print("[M2.2 smoke] \(lines.count) lines → \(totalEvents) events")
        print("[M2.2 smoke] by type:")
        for (t, n) in byType.sorted(by: { $0.value > $1.value }) {
            print("  \(t.rawValue): \(n)")
        }
        XCTAssertGreaterThan(totalEvents, 0)
        // 至少有 user_message 和 assistant_text
        XCTAssertNotNil(byType[.userMessage])
    }
```

- [ ] **Step 3: 跑并看 stdout**

```bash
swift test --filter JSONLParserTests/test_localRealSession_parses 2>&1 | grep "M2.2 smoke"
```

期望 print 出事件类型分布,肉眼核对看起来合理(user_message 几个,assistant_text 几个,tool_use + tool_result 成对出现几十,api_usage 和 assistant_text 成对)。

- [ ] **Step 4: commit**

```bash
git add Tests/CairnClaudeTests/Parser/JSONLParserTests.swift
git commit -m "test(m2.2): real-session JSONL smoke (skip if file absent)"
```

---

### Task 12: 用户验收

**Acceptance script**(你执行):

```bash
# 1. 跑全测试
swift test 2>&1 | grep "Executed"
# 期望:0 failures

# 2. 看真实 session parse 输出
swift test --filter "test_localRealSession_parses" 2>&1 | grep "M2.2 smoke"
# 期望:
# [M2.2 smoke] N lines → M events
# [M2.2 smoke] by type:
#   tool_use: X
#   tool_result: X(和 tool_use 数量接近)
#   api_usage: Y
#   assistant_text: Y
#   user_message: Z
```

**验收项(5 项)**:

| # | 检查 | 期望 |
|---|---|---|
| 1 | 全测试 pass | ~161 tests, 0 failures |
| 2 | 真实 session parse 不崩 | smoke test 有事件输出 |
| 3 | tool_use/tool_result 数量接近 | ±10% 内(极少数未配对是正常的 —— 还在活跃中) |
| 4 | api_usage 和 assistant_text 数量接近 | 每个 assistant entry 一般一条 api_usage,text/thinking/tool_use 加起来数量匹配 |
| 5 | event 类型无奇怪值 | 只出现 spec §4.3 定义的 EventType case,没有异常 |

---

## Known limitations(留给后续 milestone)

- **事件不落盘**:本 milestone 只解析,parser 输出被丢弃;M2.3 加 EventIngestor 做批量事务写 events 表
- **pairedEventId 不是 DB stable id**:parser 每次 parse 同一行生成新 UUID;tracker.observe 用 parser UUID 填 pairedEventId。M2.3 EventIngestor **必须先 DAO upsert 用 `(sessionId, lineNumber, blockIndex)` 唯一约束换回 DB stable id、覆盖 `event.id`,再调 tracker.observe**。否则 tool_result.paired_event_id 指向不存在的 id(events 表 schema 故意不加 FK,不会崩但 UI 关联失败)。这个顺序是 M2.3 的硬约束,写在 M2.3 plan 开头提醒
- **cross-entry 配对**:`ToolPairingTracker` 只管单 session 内的 tool_use/result;跨 session 的配对语义 Anthropic 不支持,不需要做
- **重启 DB 重建**:`restore(from:)` 接口定义了,但真正从 DB 读 Events 喂进来的集成在 M2.3
- **is_error 语义细化**:有的 is_error 代表真错误,有的代表用户 Ctrl+C;M2.4 Timeline 再区分
- **session 生命周期**:parser 不设置 session state;M2.6 用时间窗 + 悬挂 tool_use 启发式判定
- **compact-title/custom-title**:返回空;M3.x Task.title 更新时消费
- **system entry 的 cwd**:parser 不提取(返回空 Event 数组);M2.6 做 session ↔ workspace 映射时单独解析
- **SwiftLog**:warning 用 stderr 直写;M2.7 统一到 swift-log

---

## 完成定义

T1–T11 全部 checkbox 打勾 + 用户 T12 回 ✅ + `git tag m2-2-done` + `docs/milestone-log.md` 追 M2.2 条目。
