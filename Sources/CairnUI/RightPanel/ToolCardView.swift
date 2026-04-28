import SwiftUI
import CairnCore

/// 配对的 tool_use + tool_result 卡片。折叠态一行,展开态显示 input/output。
/// spec §4.4:"配对的 use + result 折叠为一张工具卡片,默认一行摘要,点开展开"。
public struct ToolCardView: View {
    let toolUse: Event
    let toolResult: Event?
    let isExpanded: Bool
    let onToggle: () -> Void

    public init(
        toolUse: Event, toolResult: Event?,
        isExpanded: Bool, onToggle: @escaping () -> Void
    ) {
        self.toolUse = toolUse
        self.toolResult = toolResult
        self.isExpanded = isExpanded
        self.onToggle = onToggle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 卡头 —— 总是可见
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: EventStyleMap.symbol(for: toolUse))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EventStyleMap.tint(for: toolUse))
                    .frame(width: 16, alignment: .center)

                Text(toolUse.summary)
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                statusBadge

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            // 展开态详情
            if isExpanded {
                detail
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .background(
            isError
                ? Color.red.opacity(0.06)
                : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 4)
        )
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var isError: Bool {
        toolResult?.type == .error
            || (toolResult?.summary.lowercased().contains("error") ?? false)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if toolResult != nil {
            Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(isError ? Color.red : Color.green)
        } else {
            ProgressView()
                .controlSize(.mini)
        }
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            // input
            VStack(alignment: .leading, spacing: 2) {
                Text("input").font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(extractInputSummary(toolUse.rawPayloadJson))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(12)
            }
            // output(若有)
            if let result = toolResult {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isError ? "error" : "output")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(result.summary)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isError ? .red : .secondary)
                        .textSelection(.enabled)
                        .lineLimit(20)
                }
            } else {
                Text("running…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 从 rawPayloadJson 里粗略提取 input 字段,JSON 简化显示。
    /// M2.5 简化:直接找 "input" 位置显示原文截断;找不到显示 summary。
    private func extractInputSummary(_ raw: String?) -> String {
        guard let raw = raw else { return toolUse.summary }
        // 粗 regex:提取 `"input":{ ... }` 的大致 JSON 段
        if let range = raw.range(of: "\"input\":"),
           let close = raw.range(of: "}", range: range.upperBound..<raw.endIndex) {
            let segment = raw[range.upperBound...close.upperBound]
            return String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return toolUse.summary
    }
}
