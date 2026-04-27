import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI 封装的 SwiftTerm 终端视图。
/// **M1.4 重构**:从 TabSession 取既有 NSView,不再每次创建。
/// 这样在多 tab ZStack 里 tab 切换(.opacity toggle)不会导致 NSView
/// 被销毁,PTY 进程和滚动缓冲保留。
///
/// M1.4 之前的无参版本(M0.2 单 tab 场景)已废弃,不再保留。
public struct TerminalSurface: NSViewRepresentable {
    private let session: TabSession

    public init(session: TabSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        // 不创建新 view,返回 session 持有的(在 TabSession.init 时 create)。
        // 这是多 tab 保活的关键。
        return session.terminalView
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // 不响应 state change。字号 / 主题动态切换留 M3.x。
    }
}
