import Foundation

/// 任务级 token / 成本 / 时间预算。spec §2.4。
///
/// v1 观察模式:到达 80% / 100% 只告警,不打断(spec §2.4)。
/// v1.1 Hook 启用后才会拦截(M1 不实现拦截逻辑,只持有状态)。
public struct Budget: Codable, Equatable, Hashable, Sendable {
    public let taskId: UUID

    // Pre-commitment(可选,全 nil 表示无限制 = 永远 normal)
    public var maxInputTokens: Int?
    public var maxOutputTokens: Int?
    public var maxCostUSD: Double?
    public var maxWallSeconds: Int?

    // Actual(累加 api_usage 事件)
    public var usedInputTokens: Int
    public var usedOutputTokens: Int
    public var usedCostUSD: Double
    public var usedWallSeconds: Int

    public var state: BudgetState
    public var updatedAt: Date

    public init(
        taskId: UUID,
        maxInputTokens: Int? = nil,
        maxOutputTokens: Int? = nil,
        maxCostUSD: Double? = nil,
        maxWallSeconds: Int? = nil,
        usedInputTokens: Int = 0,
        usedOutputTokens: Int = 0,
        usedCostUSD: Double = 0,
        usedWallSeconds: Int = 0,
        state: BudgetState = .normal,
        updatedAt: Date = Date()
    ) {
        self.taskId = taskId
        self.maxInputTokens = maxInputTokens
        self.maxOutputTokens = maxOutputTokens
        self.maxCostUSD = maxCostUSD
        self.maxWallSeconds = maxWallSeconds
        self.usedInputTokens = usedInputTokens
        self.usedOutputTokens = usedOutputTokens
        self.usedCostUSD = usedCostUSD
        self.usedWallSeconds = usedWallSeconds
        self.state = state
        self.updatedAt = updatedAt
    }

    /// 根据 used vs max 比例**推导**state,不修改 self(纯函数)。
    ///
    /// 规则:
    /// - `state == .paused` → 保持 .paused(paused 由用户手动设置)
    /// - 任何一个 cap 被超(used >= max)→ `.exceeded`
    /// - 任何一个 cap 到达 80%(used / max >= 0.80)→ `.warning80`
    /// - 其他 → `.normal`
    public func computeState() -> BudgetState {
        if state == .paused { return .paused }

        var maxRatio = 0.0
        var anyExceeded = false

        if let cap = maxInputTokens, cap > 0 {
            let ratio = Double(usedInputTokens) / Double(cap)
            maxRatio = max(maxRatio, ratio)
            if usedInputTokens >= cap { anyExceeded = true }
        }
        if let cap = maxOutputTokens, cap > 0 {
            let ratio = Double(usedOutputTokens) / Double(cap)
            maxRatio = max(maxRatio, ratio)
            if usedOutputTokens >= cap { anyExceeded = true }
        }
        if let cap = maxCostUSD, cap > 0 {
            let ratio = usedCostUSD / cap
            maxRatio = max(maxRatio, ratio)
            if usedCostUSD >= cap { anyExceeded = true }
        }
        if let cap = maxWallSeconds, cap > 0 {
            let ratio = Double(usedWallSeconds) / Double(cap)
            maxRatio = max(maxRatio, ratio)
            if usedWallSeconds >= cap { anyExceeded = true }
        }

        if anyExceeded { return .exceeded }
        if maxRatio >= 0.80 { return .warning80 }
        return .normal
    }
}

/// Budget 状态(4 态)。spec §2.4。
public enum BudgetState: String, Codable, CaseIterable, Sendable {
    case normal
    case warning80
    case exceeded
    case paused
}
