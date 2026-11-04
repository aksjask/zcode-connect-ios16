import SwiftUI

struct AppShell: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    // 主题色是全局单例设置；在根部订阅它，切换主题时整个 UI 重新求值并刷新 accent。
    @ObservedObject private var themePrefs = ThemePreferences.shared
    var body: some View {
        NavigationStack(path: $store.path) {
            Group {
                if store.requiresInitialConnection {
                    PairingView(embedded: true, onboarding: true)
                } else {
                    HomeView()
                }
            }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .session(let id): ChatView(sessionID: id)
                    case .newSession: NewSessionView()
                    }
                }
        }
        .tint(themePrefs.selection.color)
        .modifier(FloatingPanelOverlay())
        .sheet(item: $store.sheet) { destination in
            switch destination {
            case .connections: ConnectionsView()
            case .settings: SettingsView()
            case .pairing: PairingView()
            case .advanced: AdvancedSettingsView()
            case .files(let id, let modified): FilesView(sessionID: id, initiallyModified: modified)
            case .agent(let agent): AgentDetailView(agent: agent)
            case .voice: VoiceCaptureView()
            case .mirror: MirrorSheet()
            case .ipaTools: IPAInstallerView(showClose: true)
            case .allProjects: AllProjectsView()
            }
        }
        .alert("暂时无法完成", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .overlay(alignment: .top) {
            if let toast = store.toast {
                Text(toast).font(.subheadline).padding(.horizontal, 18).padding(.vertical, 12)
                    .compatGlassEffect(.regular, in: Capsule())
                    .padding(.top, 8).transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
        .task {
            store.completionEventSink = { sessionID, title in
                Task { await TaskNotifications.shared.postCompletion(sessionID: sessionID, title: title) }
            }
            await store.start()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--mirror-auto") { store.sheet = .mirror }
            #endif
        }
        .task {
            #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("--performance-probe") else { return }
            MotionPerformanceProbe.shared.start(sessionName: "scroll-review", metadata: ["configuration": "Debug", "arguments": ProcessInfo.processInfo.arguments.filter { $0.hasPrefix("--") }.joined(separator: " ")])
            do {
                try await Task.sleep(for: .seconds(60))
                try await MotionPerformanceProbe.shared.stopAndWrite(to: URL.documentsDirectory.appending(path: "scroll-probe.json"))
            } catch { MotionPerformanceProbe.shared.stopWithoutWriting() }
            #endif
        }
        .compatChange(of: scenePhase) { phase in
            if phase == .active {
                TaskNotifications.shared.endBackgroundWindow()
                if store.completionNotifications, store.hasConnectedBefore {
                    Task { await TaskNotifications.shared.requestAuthorizationIfNeeded() }
                }
                Task { await store.applicationDidBecomeActive() }
            } else if phase == .background {
                store.applicationDidEnterBackground()
                TaskNotifications.shared.beginBackgroundWindowIfRunning()
            }
        }
    }
}
