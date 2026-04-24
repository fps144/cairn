import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI 封装的 SwiftTerm 终端视图。M0.2 只跑用户默认 shell,
/// 不做 cwd 跟踪(OSC 7 留 M1.5)、不做 delegate 回调(留 M1.4)。
///
/// 关键 API 事实(SwiftTerm 1.13.0 源码核实):
/// - `LocalProcessTerminalView: TerminalView` 其中 `TerminalView: NSView`,
///   因此可直接作为 `NSViewRepresentable.NSViewType`
/// - `startProcess` 完整签名:
///   `(executable: String = "/bin/bash", args: [String] = [],
///     environment: [String]? = nil, execName: String? = nil,
///     currentDirectory: String? = nil)`
/// - environment 传 nil 时 SwiftTerm 用合理默认(继承 PATH/HOME 等),
///   无需手动构造(SwiftTerm 内部做)
/// - execName 传 "-" + basename(shell) → shell 启动为 login shell,
///   加载 .zprofile,与官方 TerminalApp/MacTerminal 示例一致
public struct TerminalSurface: NSViewRepresentable {
    private let shell: String
    private let cwd: String?

    /// - Parameters:
    ///   - shell: 要启动的 shell 可执行路径。nil 时用 `$SHELL` 环境变量,兜底 `/bin/zsh`。
    ///   - cwd: 起始工作目录。nil 时 SwiftTerm 继承父进程 cwd。
    public init(shell: String? = nil, cwd: String? = nil) {
        self.shell = shell
            ?? ProcessInfo.processInfo.environment["SHELL"]
            ?? "/bin/zsh"
        self.cwd = cwd
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        // login shell idiom:`/bin/zsh` → `-zsh`,让 shell 加载 .zprofile
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        view.startProcess(
            executable: shell,
            args: [],
            environment: nil,       // SwiftTerm 用默认 env,M1.4 再注入 CAIRN_* 标识
            execName: shellIdiom,
            currentDirectory: cwd   // nil = 继承,非 nil = 精确设置,M1.5 OSC 7 修正
        )
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // M0.2 不响应 state change。后续 milestone 在此处理字号 / 主题动态切换。
    }
}
