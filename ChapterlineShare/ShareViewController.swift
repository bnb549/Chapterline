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

    /// Info.plist `NSExtensionActivationRule` is the share-sheet gate.
    /// `ShareImportAllowlist` applies that same list again and caps one share at 20 files.
    private func copyAttachments() async {
        guard let inbox = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.benmonroe.ChapterLine")?
            .appendingPathComponent("Inbox", isDirectory: true) else {
            finish(cancelled: true)
            return
        }
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var copied = 0
        for item in items {
            for provider in item.attachments ?? [] {
                if copied >= ShareImportAllowlist.maxAttachmentCount { break }
                guard let url = await loadFileURL(from: provider) else { continue }
                guard ShareImportAllowlist.allowsFile(
                    typeIdentifiers: provider.registeredTypeIdentifiers,
                    pathExtension: url.pathExtension
                ) else { continue }
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
            }
            if copied >= ShareImportAllowlist.maxAttachmentCount { break }
        }

        let notification = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(notification, CFNotificationName("com.benmonroe.ChapterLine.import" as CFString), nil, nil, true)
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

    /// File URLs only. Unrecognized bytes are skipped, not written out as a book.
    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        let fileURLTypes = [UTType.fileURL.identifier, "public.file-url"]
        for type in fileURLTypes where provider.hasItemConformingToTypeIdentifier(type) {
            if let url = await loadURLItem(from: provider, typeIdentifier: type, acceptBookmarkData: true) {
                return url
            }
        }
        for type in ShareImportAllowlist.typeIdentifiers where provider.hasItemConformingToTypeIdentifier(type) {
            if let url = await loadURLItem(from: provider, typeIdentifier: type, acceptBookmarkData: false) {
                return url
            }
        }
        return nil
    }

    private func loadURLItem(
        from provider: NSItemProvider,
        typeIdentifier: String,
        acceptBookmarkData: Bool
    ) async -> URL? {
        let loaded = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
        if let url = loaded as? URL {
            return url
        }
        if acceptBookmarkData, let data = loaded as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return url
        }
        return nil
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
