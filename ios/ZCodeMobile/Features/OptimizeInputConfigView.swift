import SwiftUI

/// 「优化输入 · 模型配置」——对应桌面端同名配置页的手机版本。
struct OptimizeInputConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = OptimizeInputConfig.load()
    @State private var testing = false
    @State private var testResult: String?
    @State private var showKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("接口协议", selection: $config.apiProtocol) {
                        Text("openai").tag("openai")
                        Text("anthropic").tag("anthropic")
                    }
                    TextField("Base URL（填到版本一级）", text: $config.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Group {
                            if showKey {
                                TextField("API Key", text: $config.apiKey)
                            } else {
                                SecureField("API Key", text: $config.apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        Button { showKey.toggle() } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye").foregroundStyle(.secondary)
                        }.buttonStyle(.borderless)
                    }
                    TextField("模型，如 glm-4.5-air", text: $config.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("超时", text: Binding(
                            get: { String(config.timeoutMs) },
                            set: { config.timeoutMs = Int($0.filter(\.isNumber)) ?? config.timeoutMs }))
                            .keyboardType(.numberPad)
                        Spacer()
                        Text("毫秒").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("模型配置")
                } footer: {
                    Text("接口协议：openai = /chat/completions，anthropic = /v1/messages。配置保存在手机本机（桌面端保存在 ~\\.optimize-input.json，两边互不影响）。开启后发送消息会先用此模型把输入润色一遍。")
                }

                Section("测试") {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if testing { ProgressView().controlSize(.small) }
                            Text(testing ? "测试中…" : "测试连接")
                        }
                    }
                    .disabled(testing || !config.isValid)
                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundColor(testResult.hasPrefix("✅") ? .green : .red)
                    }
                }
            }
            .navigationTitle("优化输入 · 模型配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        config.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func testConnection() {
        testResult = nil
        testing = true
        Task {
            do {
                let reply = try await OptimizeInputService(config: config).testConnection()
                testResult = "✅ 连接成功：\(reply.prefix(40))"
            } catch {
                testResult = "❌ \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
