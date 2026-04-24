import XCTest
@testable import CairnCore

final class ToolCategoryTests: XCTestCase {
    func test_staticConstants_coverSpecCategories() {
        // spec §2.3 列出的 12 种 category
        let expected: Set<String> = [
            "shell", "file_read", "file_write", "file_search",
            "web_fetch", "mcp_call", "subagent", "todo",
            "plan_mgmt", "ask_user", "ide", "other",
        ]
        let allStatic: [ToolCategory] = [
            .shell, .fileRead, .fileWrite, .fileSearch,
            .webFetch, .mcpCall, .subagent, .todo,
            .planMgmt, .askUser, .ide, .other,
        ]
        XCTAssertEqual(Set(allStatic.map(\.rawValue)), expected)
    }

    func test_fromToolName_shellTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Bash"), .shell)
    }

    func test_fromToolName_fileReadTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Read"), .fileRead)
        XCTAssertEqual(ToolCategory.from(toolName: "NotebookRead"), .fileRead)
    }

    func test_fromToolName_fileWriteTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Write"), .fileWrite)
        XCTAssertEqual(ToolCategory.from(toolName: "Edit"), .fileWrite)
        XCTAssertEqual(ToolCategory.from(toolName: "NotebookEdit"), .fileWrite)
    }

    func test_fromToolName_searchTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "Glob"), .fileSearch)
        XCTAssertEqual(ToolCategory.from(toolName: "Grep"), .fileSearch)
    }

    func test_fromToolName_webTools() {
        XCTAssertEqual(ToolCategory.from(toolName: "WebFetch"), .webFetch)
        XCTAssertEqual(ToolCategory.from(toolName: "WebSearch"), .webFetch)
    }

    func test_fromToolName_mcpPrefix() {
        XCTAssertEqual(ToolCategory.from(toolName: "mcp__feishu-mcp__fetch-doc"), .mcpCall)
        XCTAssertEqual(ToolCategory.from(toolName: "ListMcpResourcesTool"), .mcpCall)
    }

    func test_fromToolName_ideSubPrefix() {
        // mcp__ide__* 是 mcpCall 的特化 → ide
        XCTAssertEqual(ToolCategory.from(toolName: "mcp__ide__getDiagnostics"), .ide)
    }

    func test_fromToolName_subagent() {
        XCTAssertEqual(ToolCategory.from(toolName: "Agent"), .subagent)
        XCTAssertEqual(ToolCategory.from(toolName: "Task"), .subagent,
                       "Claude Code 的 Task 工具是 agent,不是 task 实体")
    }

    func test_fromToolName_todoAndTaskMgmt() {
        XCTAssertEqual(ToolCategory.from(toolName: "TodoWrite"), .todo)
        // M0.1 probe 扩展:TaskCreate / TaskUpdate / TaskList 等归入 todo
        XCTAssertEqual(ToolCategory.from(toolName: "TaskCreate"), .todo)
        XCTAssertEqual(ToolCategory.from(toolName: "TaskUpdate"), .todo)
        XCTAssertEqual(ToolCategory.from(toolName: "TaskList"), .todo)
    }

    func test_fromToolName_planMgmt() {
        XCTAssertEqual(ToolCategory.from(toolName: "EnterPlanMode"), .planMgmt)
        XCTAssertEqual(ToolCategory.from(toolName: "ExitPlanMode"), .planMgmt)
    }

    func test_fromToolName_askUser() {
        XCTAssertEqual(ToolCategory.from(toolName: "AskUserQuestion"), .askUser)
    }

    func test_fromToolName_unknownFallsToOther() {
        XCTAssertEqual(ToolCategory.from(toolName: "SomeUnknownTool"), .other)
        XCTAssertEqual(ToolCategory.from(toolName: ""), .other)
    }

    func test_customCategory_viaRawValue() {
        let custom = ToolCategory(rawValue: "experimental_category_v1")
        XCTAssertEqual(custom.rawValue, "experimental_category_v1")
        // custom 不等于任何静态常量
        XCTAssertNotEqual(custom, .other)
    }

    func test_codable_roundTrip() throws {
        for sample in [ToolCategory.shell, .mcpCall, .ide, .other,
                       ToolCategory(rawValue: "custom")] {
            let data = try JSONEncoder().encode(sample)
            let decoded = try JSONDecoder().decode(ToolCategory.self, from: data)
            XCTAssertEqual(sample, decoded)
        }
    }
}
