import FormlessCore
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        NavigationSplitView {
            QueueList()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            if let selected = state.selected, let spec = selected.spec {
                DetailView(
                    item: selected, spec: spec,
                    onBriefChanged: { state.queue.persistBrief(selected) })
            } else {
                EmptyDetail()
            }
        }
        .toolbar { Toolbar() }
        // 窗口本身也接受拖放，不只是菜单栏图标
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: state.queue.activeCount) { _, _ in
            state.syncBusyIndicator()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                guard
                    let item = try? await provider.loadItem(
                        forTypeIdentifier: UTType.fileURL.identifier),
                    let data = item as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil)
                else { continue }
                // 只收图片
                if let type = UTType(filenameExtension: url.pathExtension),
                    type.conforms(to: .image)
                {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { state.queue.enqueue(urls) }
        }
        return true
    }
}

// MARK: - 队列列表

private struct QueueList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Group {
            if state.queue.items.isEmpty {
                EmptyQueue()
            } else {
                List(selection: $state.selected) {
                    ForEach(state.queue.items) { item in
                        QueueRow(item: item)
                            .tag(item)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .safeAreaInset(edge: .bottom) { QueueFooter() }
    }
}

private struct QueueRow: View {
    @Environment(AppState.self) private var state
    let item: QueueItem

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailView(url: item.imageURL, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.system(size: 12, weight: .medium))

                StatusBadge(status: item.status)
            }

            Spacer(minLength: 0)

            if case .failed = item.status {
                Button {
                    state.queue.retry(item)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("重试")
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            if case .failed = item.status {
                Button("重试") { state.queue.retry(item) }
            }
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.imageURL])
            }
            Divider()
            Button("从队列移除", role: .destructive) {
                if state.selected == item { state.selected = nil }
                state.queue.remove(item)
            }
        }
    }
}

private struct StatusBadge: View {
    let status: AnalysisStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .waiting:
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text("等待").foregroundStyle(.secondary)
            case .analyzing:
                ProgressView().controlSize(.mini)
                Text("分析中").foregroundStyle(.secondary)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("完成").foregroundStyle(.secondary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            }
        }
        .font(.system(size: 10))
    }
}

private struct QueueFooter: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let q = state.queue
        HStack(spacing: 8) {
            Text("\(q.doneCount)/\(q.items.count) 完成")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            if q.isPaused {
                Button("继续") { q.resume() }
                    .controlSize(.small)
            } else if q.activeCount > 0 {
                Button("暂停") { q.pause() }
                    .controlSize(.small)
            }

            if !q.autoAnalyze && q.pendingCount > 0 {
                Button("开始分析") { q.startPending() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - 空态

private struct EmptyQueue: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("把图片拖到菜单栏 ✨ 图标上")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("或直接拖到这个窗口")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Button("导入文件夹…") { state.onImportFolderRequested?() }
                .controlSize(.small)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyDetail: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            Text("选一张已完成的图查看风格")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 工具栏

private struct Toolbar: ToolbarContent {
    @Environment(AppState.self) private var state

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.onImportFolderRequested?()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("导入文件夹")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.queue.clearCompleted()
                state.selected = nil
            } label: {
                Image(systemName: "trash")
            }
            .help("清除已完成")
            .disabled(state.queue.doneCount == 0)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                state.onSettingsRequested?()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
    }
}
