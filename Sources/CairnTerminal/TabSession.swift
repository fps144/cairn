import Foundation
import AppKit
import Observation
import SwiftTerm
import CairnCore

/// 一个 live 终端 tab 的句柄。包装 SwiftTerm `LocalProcessTerminalView`
/// 实例 + Cairn 领域元数据。
///
/// 跨 UI 重绘保活:本类是 @MainActor class,强引用 terminalView。
/// TerminalSurface.makeNSView 返回 session.terminalView(既有),
/// tab 切换时 NSView 不被销毁,PTY 进程和滚动缓冲保留。
///
/// **M1.5 升级为 @Observable**:OSC 7 动态改 title / cwd 时,
/// SwiftUI 追踪改动,TabBarView 自动重渲染。
@Observable
@MainActor
public final class TabSession: Identifiable, Equatable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    /// shell 的当前 cwd。OSC 7 escape 上报时由 updateCwd 更新。
    public var cwd: String
    /// 启动 shell 的路径(从 $SHELL 或默认 /bin/zsh)。
    public let shell: String
    /// `TabState.active`(进程运行中)或 `.closed`(进程已退出)。
    public var state: TabState
    /// 底层 SwiftTerm view(NSView 子类)。整个 TabSession 生命周期不变。
    public let terminalView: LocalProcessTerminalView

    /// 强引用 ProcessTerminationObserver。SwiftTerm 的 processDelegate
    /// 是 weak,若不强持 observer,exit 回调会丢失。
    internal var processObserver: ProcessTerminationObserver?

    public init(
        id: UUID = UUID(),
        workspaceId: UUID,
        title: String,
        cwd: String,
        shell: String,
        terminalView: LocalProcessTerminalView
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.title = title
        self.cwd = cwd
        self.shell = shell
        self.state = .active
        self.terminalView = terminalView
    }

    /// 强制杀 PTY 进程。optional chain 防测试里未 startProcess 的 session 调用 crash。
    public func terminate() {
        terminalView.process?.terminate()
        state = .closed
    }

    /// OSC 7 上报新 cwd 时调用。同时更新 title(basename 反映当前目录)。
    /// guard 跳过相同值避免 @Observable 无效 trigger。
    public func updateCwd(_ newCwd: String) {
        guard newCwd != cwd else { return }
        cwd = newCwd
        let basename = (newCwd as NSString).lastPathComponent
        let shellName = (shell as NSString).lastPathComponent
        title = "\(basename.isEmpty ? "~" : basename) (\(shellName))"
    }

    public static func == (lhs: TabSession, rhs: TabSession) -> Bool {
        lhs.id == rhs.id
    }
}

/// Factory:创建 TabSession 时同步启动 PTY 进程。
@MainActor
public enum TabSessionFactory {
    /// 创建新 TabSession + 启动 shell 进程 + 挂 OSC 7 / processTerminated delegate。
    public static func create(
        workspaceId: UUID,
        shell shellPath: String? = nil,
        cwd startCwd: String? = nil,
        onProcessTerminated: @escaping @MainActor (Int32?) -> Void
    ) -> TabSession {
        let shell = shellPath
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        let cwd = startCwd
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "/"
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        let basename = (cwd as NSString).lastPathComponent
        let shellName = (shell as NSString).lastPathComponent
        let title = "\(basename.isEmpty ? "~" : basename) (\(shellName))"

        let view = LocalProcessTerminalView(frame: .zero)

        // Observer 需要在 startProcess 前挂;但 onCwdUpdate callback 需要引用
        // 尚未构造的 session。SessionHolder forward-ref 解决:holder weak 指向
        // session,session 构造后填 holder,observer callback 通过 holder
        // 拿 session 调 updateCwd。
        let sessionHolder = SessionHolder()
        let observer = ProcessTerminationObserver(
            onTerminated: onProcessTerminated,
            onCwdUpdate: { [weak sessionHolder] newCwd in
                sessionHolder?.session?.updateCwd(newCwd)
            }
        )
        view.processDelegate = observer

        view.startProcess(
            executable: shell,
            args: [],
            environment: nil,
            execName: shellIdiom,
            currentDirectory: cwd
        )

        let session = TabSession(
            workspaceId: workspaceId,
            title: title,
            cwd: cwd,
            shell: shell,
            terminalView: view
        )
        session.processObserver = observer
        sessionHolder.session = session
        return session
    }
}

/// Observer 先构造 / session 后构造的 forward-ref 容器。
/// private 限定本文件内部使用。
@MainActor
private final class SessionHolder {
    weak var session: TabSession?
}

/// 监听 LocalProcessTerminalView 的 delegate 事件:
/// - processTerminated: shell 退出
/// - hostCurrentDirectoryUpdate: OSC 7 cwd 上报
///
/// 其他 delegate 方法(sizeChanged / setTerminalTitle)本 milestone 不处理。
@MainActor
public final class ProcessTerminationObserver: NSObject, LocalProcessTerminalViewDelegate {
    public typealias TerminationCallback = @MainActor (_ exitCode: Int32?) -> Void
    public typealias CwdUpdateCallback = @MainActor (_ newDirectory: String) -> Void

    private let onTerminated: TerminationCallback
    private let onCwdUpdate: CwdUpdateCallback

    public init(
        onTerminated: @escaping TerminationCallback,
        onCwdUpdate: @escaping CwdUpdateCallback
    ) {
        self.onTerminated = onTerminated
        self.onCwdUpdate = onCwdUpdate
        super.init()
    }

    // MARK: - LocalProcessTerminalViewDelegate
    // SwiftTerm 1.13 协议:4 方法 source 类型混用,保持原样。

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // v1 无需处理(SwiftTerm 内部已发 TIOCSWINSZ)
    }

    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // v1 不用 OSC 2/1 标题(M1.5 OSC 7 cwd 更贴近需求)
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory,
              let parsed = OSC7Parser.parse(directory) else { return }
        onCwdUpdate(parsed)
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTerminated(exitCode)
    }
}
