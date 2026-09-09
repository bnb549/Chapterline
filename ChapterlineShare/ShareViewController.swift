import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "Adding to Chapterline…"
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        Task { await copyAttachments() }
    }

    private func copyAttachments() async {
        guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.benmonroe.free-player")?
            .appendingPathComponent("Inbox", isDirectory: true) else {
            finish(cancelled: true)
            return
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var copied = 0
        for item in items {
            for provider in item.attachments ?? [] {
                if let url = await loadURL(from: provider) {
                    let dest = inbox.appendingPathComponent(uniqueName(url.lastPathComponent, in: inbox))
                    do {
                        if url.startAccessingSecurityScopedResource() {
                            defer { url.stopAccessingSecurityScopedResource() }
                            try FileManager.default.copyItem(at: url, to: dest)
                        } else {
                            try FileManager.default.copyItem(at: url, to: dest)
                        }
                        copied += 1
                    } catch {
                        continue
                    }
                } else if let data = await loadData(from: provider) {
                    let dest = inbox.appendingPathComponent("share-\(UUID().uuidString).m4b")
                    try? data.write(to: dest)
                    copied += 1
                }
            }
        }

        let notification = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(notification, CFNotificationName("com.benmonroe.free-player.import" as CFString), nil, nil, true)
        finish(cancelled: copied == 0)
    }

    private func uniqueName(_ name: String, in directory: URL) -> String {
        var candidate = name
        var step = 1
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            candidate = ext.isEmpty ? "\(base)-\(step)" : "\(base)-\(step).\(ext)"
            step += 1
        }
        return candidate
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        let types = [UTType.fileURL.identifier, UTType.audiovisualContent.identifier, "public.file-url"]
        for type in types where provider.hasItemConformingToTypeIdentifier(type) {
            let loaded = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    continuation.resume(returning: item)
                }
            }
            if let url = loaded as? URL {
                return url
            }
            if let data = loaded as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                return url
            }
        }
        return nil
    }

    private func loadData(from provider: NSItemProvider) async -> Data? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func finish(cancelled: Bool) {
        DispatchQueue.main.async {
            if cancelled {
                self.extensionContext?.cancelRequest(withError: NSError(domain: "ChapterlineShare", code: 1))
            } else {
                self.extensionContext?.completeRequest(returningItems: nil)
            }
        }
    }
}
