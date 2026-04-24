import SwiftUI

/// Cairn 主内容视图。M0.2 里只占位,T7 嵌入 TerminalSurface。
public struct ContentView: View {
    public init() {}

    public var body: some View {
        // T7 将用 TerminalSurface 替换下面这段 VStack
        VStack(spacing: 12) {
            Text("Cairn")
                .font(.largeTitle)
                .bold()
            Text("M0.2 scaffold · Terminal integration pending (T7)")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
