import XCTest
import SwiftUI
import CairnCore
@testable import CairnUI

@MainActor
final class EventRowViewTests: XCTestCase {
    /// smoke:确保每种 EventType 渲染不崩(EventStyleMap 映射完整)。
    func test_doesNotCrashForAllEventTypes() {
        for type in EventType.allCases {
            let e = Event(sessionId: UUID(), type: type,
                          timestamp: Date(), lineNumber: 1, summary: "smoke")
            let view = EventRowView(event: e)
            _ = view.body
        }
    }

    /// ToolCategory 各 case 也覆盖(toolUse 分支)
    func test_doesNotCrashForCommonToolCategories() {
        let cats: [ToolCategory] = [
            .shell, .fileRead, .fileWrite, .fileSearch, .webFetch,
            .mcpCall, .subagent, .todo, .planMgmt, .askUser, .ide, .other
        ]
        for cat in cats {
            let e = Event(
                sessionId: UUID(), type: .toolUse, category: cat,
                toolName: "X", toolUseId: "tu_1",
                timestamp: Date(), lineNumber: 1, summary: "X()"
            )
            _ = EventRowView(event: e).body
        }
    }
}
