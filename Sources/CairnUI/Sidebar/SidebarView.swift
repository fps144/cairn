import SwiftUI
import CairnCore
import CairnServices

/// Sidebar:Task 列表(按 Workspace 分组)。spec §6.2。
/// M3.1 渲染 active workspace 的 task 列表;workspace 多选留 M3.5。
public struct SidebarView: View {
    let vm: TaskListViewModel?
    let activeBoundSessionId: UUID?
    let onTapTask: (CairnTask) -> Void

    public init(
        vm: TaskListViewModel?,
        activeBoundSessionId: UUID?,
        onTapTask: @escaping (CairnTask) -> Void = { _ in }
    ) {
        self.vm = vm
        self.activeBoundSessionId = activeBoundSessionId
        self.onTapTask = onTapTask
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            searchPlaceholder
            Divider()
            content
        }
    }

    private var header: some View {
        HStack {
            Text("Tasks")
                .font(.title3)
                .bold()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchPlaceholder: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Search tasks")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let vm, !vm.tasks.isEmpty {
            ScrollView {
                LazyVStack(spacing: 2) {
                    let highlightedId = vm.highlightedTaskId(
                        forActiveSessionId: activeBoundSessionId
                    )
                    ForEach(vm.tasks, id: \.id) { task in
                        TaskRow(
                            task: task,
                            isHighlighted: task.id == highlightedId
                        )
                        .onTapGesture { onTapTask(task) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No tasks yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Tasks from your Claude Code sessions will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview {
    SidebarView(vm: nil, activeBoundSessionId: nil)
        .frame(width: 280, height: 600)
}
#endif
