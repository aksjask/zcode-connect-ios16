import SwiftUI
import UIKit

/// URL 导入安装：粘贴 IPA/TIPA 直链（如局域网共享服务器），
/// 可直接唤起 TrollStore 拉取安装，或下载到手机后经分享面板交给巨魔/文件 App。
struct IPAInstallerView: View {
    @State private var urlString = ""
    @State private var history: [String] = UserDefaults.standard.stringArray(forKey: "ipaInstallHistory") ?? []
    @State private var downloading = false
    @State private var receivedBytes: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var downloadedFileURL: URL?
    @State private var statusMessage: String?
    private var downloadSession: URLSession?

    private var cleanedURLString: String { urlString.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var targetURL: URL? {
        URL(string: cleanedURLString).flatMap { url in
            (url.scheme == "http" || url.scheme == "https") ? url : nil
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("https://… 或 http://192.168.1.110:8666/xxx.ipa", text: $urlString, axis: .vertical)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("ipa.urlField")
                if let fileURL = downloadedFileURL {
                    Label("已下载：\(fileURL.lastPathComponent)（\(formattedBytes(receivedBytes))）",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(.green)
                    ShareLink(item: fileURL, preview: SharePreview(fileURL.lastPathComponent)) {
                        Label("分享安装（TrollStore / 文件 App）", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("安装包直链")
            } footer: {
                Text("支持 .ipa / .tipa。「用 TrollStore 直接安装」会唤起巨魔从该网址拉取安装（TrollStore 注册的 apple-magnifier 协议）；也可以先下载到手机，再从分享面板交给 TrollStore。局域网地址需要手机与电脑在同一网络。")
            }

            Section("安装") {
                Button {
                    installViaTrollStore()
                } label: {
                    Label("用 TrollStore 直接安装", systemImage: "hammer.fill")
                }
                .disabled(targetURL == nil)
                Button {
                    download()
                } label: {
                    HStack {
                        if downloading { ProgressView().controlSize(.small) }
                        Text(downloading ? "下载中…" : "下载到手机")
                    }
                }
                .disabled(targetURL == nil || downloading)
                if downloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0)
                        Text("\(formattedBytes(receivedBytes)) / \(totalBytes > 0 ? formattedBytes(totalBytes) : "大小未知")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let statusMessage {
                    Text(statusMessage).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !history.isEmpty {
                Section {
                    ForEach(history, id: \.self) { item in
                        Button { urlString = item } label: {
                            Text(item).font(.footnote).lineLimit(1)
                        }
                    }
                    Button("清空历史", role: .destructive) {
                        history = []
                        UserDefaults.standard.set([String](), forKey: "ipaInstallHistory")
                    }
                } header: {
                    Text("最近使用")
                }
            }
        }
        .navigationTitle("IPA 安装器")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rememberHistory() {
        var items = history.filter { $0 != cleanedURLString }
        items.insert(cleanedURLString, at: 0)
        history = Array(items.prefix(8))
        UserDefaults.standard.set(history, forKey: "ipaInstallHistory")
    }

    /// TrollStore 2 注册了 apple-magnifier 协议，可直接从远程网址安装。
    private func installViaTrollStore() {
        guard let target = targetURL else { return }
        rememberHistory()
        let encoded = target.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? target.absoluteString
        guard let trollURL = URL(string: "apple-magnifier://install?url=\(encoded)") else { return }
        statusMessage = nil
        UIApplication.shared.open(trollURL) { opened in
            if !opened {
                statusMessage = "无法唤起 TrollStore：请确认设备已安装 TrollStore 2 或更高版本；也可以改用「下载到手机」后分享安装。"
            }
        }
    }

    private func download() {
        guard let target = targetURL, !downloading else { return }
        statusMessage = nil
        downloadedFileURL = nil
        receivedBytes = 0
        totalBytes = 0
        downloading = true
        rememberHistory()

        let delegate = IPADownloadDelegate()
        delegate.onProgress = { received, total in
            receivedBytes = received
            totalBytes = total
        }
        delegate.onFinish = { location, response in
            downloading = false
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                statusMessage = "下载失败：HTTP \(status)"
                return
            }
            var name = response.suggestedFilename ?? target.lastPathComponent
            if name.isEmpty { name = "app.ipa" }
            if !name.hasSuffix(".ipa") && !name.hasSuffix(".tipa") { name += ".ipa" }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                downloadedFileURL = destination
                receivedBytes = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? receivedBytes
            } catch {
                statusMessage = "保存失败：\(error.localizedDescription)"
            }
        }
        delegate.onError = { error in
            downloading = false
            statusMessage = "下载失败：\(error.localizedDescription)"
        }

        var request = URLRequest(url: target)
        request.timeoutInterval = 60
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        // session 由 delegate 持有，避免任务进行中被释放
        delegate.owningSession = session
        session.downloadTask(with: request).resume()
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// 下载回调桥：把 URLSession 委托事件转回主线程状态。
final class IPADownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var owningSession: URLSession?
    var onProgress: ((Int64, Int64) -> Void)?
    var onFinish: ((URL, URLResponse?) -> Void)?
    var onError: ((Error) -> Void)?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let received = totalBytesWritten, total = totalBytesExpectedToWrite
        DispatchQueue.main.async { self.onProgress?(received, total) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let response = downloadTask.response
        DispatchQueue.main.async { self.onFinish?(location, response) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        DispatchQueue.main.async { self.onError?(error) }
    }

    deinit {
        owningSession?.finishTasksAndInvalidate()
    }
}
