import SwiftUI
import CairnTerminal

/// Cairn 主内容视图。M0.2 里全屏嵌入一个 TerminalSurface,
/// 执行用户默认 shell。后续 milestone 加 toolbar / 分屏 / tab bar 等。
public struct ContentView: View {
    public init() {}

    public var body: some View {
        TerminalSurface()
            .frame(minWidth: 600, minHeight: 400)
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
