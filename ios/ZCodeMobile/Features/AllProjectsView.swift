import SwiftUI

/// 跨项目任务总览：逐工作区桥接扫描，聚合电脑上所有已打开项目的任务。
/// 扫描期间会短暂切换工作区桥，结束后自动恢复当前项目。
struct AllProjectsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var switchingTo: ConnectionProfile?

    var body: some View {
        NavigationStack {
            Group {
                if store.overviewLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("正在逐个项目读取任务…").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.allProjectsOverview.isEmpty {
                    CompatUnavailableView("没有可读取的项目",
                        systemImage: "square.grid.2x2",
                        description: Text("在电脑上打开项目窗口后，点下方刷新重试。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    overviewList
                }
            }
            .background(ZTheme.background)
            .navigationTitle("全部项目任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refreshAllProjectsOverview() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }.disabled(store.overviewLoading).accessibilityLabel("刷新")
                }
            }
            .onAppear { if store.allProjectsOverview.isEmpty { Task { await store.refreshAllProjectsOverview() } } }
            .confirmationDialog("切换到这个项目？", isPresented: Binding(get: { switchingTo != nil }, set: { if !$0 { switchingTo = nil } }), titleVisibility: .visible) {
                Button("连接并切换") {
                    guard let profile = switchingTo else { return }
                    switchingTo = nil
                    dismiss()
                    Task { await store.switchComputer(profile, confirmedControllerReplacement: true) }
                }
                Button("取消", role: .cancel) { switchingTo = nil }
            } message: { Text("如果另一台手机正在控制这台电脑，此次连接可能替换它。") }
        }
    }

    private var overviewList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(store.allProjectsOverview) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(ZTheme.accent)
                            Text(index.projectName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Spacer()
                            if index.isCurrent { Text("当前").font(.caption2.weight(.medium)).foregroundStyle(ZTheme.accent) }
                        }
                        if let error = index.error {
                            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        } else if index.tasks.isEmpty {
                            Text("该项目暂无任务").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(index.tasks.prefix(20)) { task in
                                HStack(spacing: 8) {
                                    StatusGlyph(status: task.status)
                                    Text(task.title).font(.system(size: 15)).lineLimit(1)
                                    Spacer()
                                    if let ms = task.updatedAt, ms > 0 {
                                        Text(Date(timeIntervalSince1970: ms / 1000), style: .relative).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if index.tasks.count > 20 {
                                Text("还有 \(index.tasks.count - 20) 个任务未显示").font(.caption2).foregroundStyle(.secondary)
                            }
                            switchAction(for: index)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ZTheme.grouped, in: RoundedRectangle(cornerRadius: 16))
                }
                Text("扫描期间会短暂切换工作区，结束后自动回到当前项目。").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
    }

    @ViewBuilder private func switchAction(for index: WorkspaceTaskIndex) -> some View {
        if !index.isCurrent, let profile = store.profiles.first(where: { $0.relayWorkspaceKey == index.workspaceKey }) {
            Button {
                switchingTo = profile
            } label: {
                Label("切换到此项目", systemImage: "arrow.triangle.swap").font(.footnote.weight(.medium))
            }.buttonStyle(CompatGlassButtonStyle(fallback: .regular))
        } else if !index.isCurrent {
            Text("连接过该项目后可一键切换").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// 独立的状态图标（供非 HomeView 页面复用）。
struct StatusGlyph: View {
    let status: String?

    var body: some View {
        switch status {
        case "running": ProgressView().controlSize(.mini).tint(ZTheme.accent).frame(width: 14, height: 14)
        case "waiting": Image(systemName: "exclamationmark.circle.fill").font(.system(size: 14)).foregroundStyle(.orange)
        case "failed": Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.red)
        case "completed": Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(ZTheme.accent)
        default: Image(systemName: "circle.dashed").font(.system(size: 14)).foregroundStyle(.tertiary)
        }
    }
}
