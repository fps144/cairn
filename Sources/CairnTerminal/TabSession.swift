import Foundation
import AppKit
import SwiftTerm
import CairnCore

/// 一个 live 终端 tab 的句柄。包装 SwiftTerm `LocalProcessTerminalView`
/// 实例 + Cairn 领域元数据(Tab 实体 + TabState)。
///
/// 跨 UI 重绘保活:本类是 @MainActor class,强引用 terminalView。
/// TerminalSurface.makeNSView 不再创建新 view,而是取 session.terminalView,
/// 这样 tab 切换时 NSView 不被销毁,PTY 进程和滚动缓冲全部保留。
@MainActor
public final class TabSession: Identifiable, Equatable {
    public let id: UUID
    public var workspaceId: UUID
    public var title: String
    /// 启动 shell 时的 cwd(spec §5.5 OSC 7 动态跟踪留 M1.5)。
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

    /// 强制杀 PTY 进程(spec §5.2 "强杀")。调用后 state = .closed。
    /// 用 optional chain(SwiftTerm 的 process 是 IUO,防测试里未 startProcess
    /// 的 session 调 terminate 时 force-unwrap crash)。
    public func terminate() {
        // SwiftTerm 1.13 的 LocalProcess.terminate() 无参(发 SIGTERM);
        // plan 初稿按 spec §5.2 "terminate(kill)" 翻成 asKillSignal: true,
        // 实测签名不对,改无参调用。
        terminalView.process?.terminate()
        state = .closed
    }

    public static func == (lhs: TabSession, rhs: TabSession) -> Bool {
        lhs.id == rhs.id
    }
}

/// Factory:创建 TabSession 时同步启动 PTY 进程。
/// 从 coordinator 调用,一次完成"创建对象 + startProcess"。
@MainActor
public enum TabSessionFactory {
    /// 创建新 TabSession + 启动 shell 进程。
    /// - Parameters:
    ///   - workspaceId: 所属 workspace id
    ///   - shell: 要启的 shell 路径;nil 时用 $SHELL,兜底 /bin/zsh
    ///   - cwd: 启动目录;nil 时用 $HOME
    ///   - onProcessTerminated: shell 退出 / crash 时的回调(强制 @MainActor)
    /// - Returns: TabSession 实例,已 startProcess
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

        // 安装 delegate(先创建 observer,startProcess 前挂上以确保
        // 进程退出事件不丢)
        let observer = ProcessTerminationObserver(onTerminated: onProcessTerminated)
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
        // 把 observer 绑到 session 上防止被 ARC 释放
        session.processObserver = observer
        return session
    }
}

/// 监听 LocalProcessTerminalView 的 processTerminated 事件。
/// 为避免 SwiftTerm 原生 delegate 协议泄漏到 coordinator,用一个
/// 内部 observer class 转发。
@MainActor
public final class ProcessTerminationObserver: NSObject, LocalProcessTerminalViewDelegate {
    public typealias Callback = @MainActor (_ exitCode: Int32?) -> Void

    private let onTerminated: Callback

    public init(onTerminated: @escaping Callback) {
        self.onTerminated = onTerminated
        super.init()
    }

    // MARK: - LocalProcessTerminalViewDelegate

    // 注:SwiftTerm 1.13 的 LocalProcessTerminalViewDelegate 协议里 4 个方法
    // 用了两种 source 类型:
    //   - sizeChanged / setTerminalTitle: source: LocalProcessTerminalView
    //   - hostCurrentDirectoryUpdate / processTerminated: source: TerminalView
    // 不要尝试统一,保持与协议原样一致。

    public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // v1 无需处理(SwiftTerm 内部已发 TIOCSWINSZ)
    }

    public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // v1 不用 OSC 2/1 标题(M1.5 OSC 7 cwd 一起考虑)
    }

    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // OSC 7 cwd 跟踪留 M1.5
    }

    public func processTerminated(source: TerminalView, exitCode: Int32?) {
        onTerminated(exitCode)
    }
}
