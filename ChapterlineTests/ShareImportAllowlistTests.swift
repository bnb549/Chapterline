import XCTest

final class ShareImportAllowlistTests: XCTestCase {
    func testExtensionsAcceptAudiobooksAndZipOnly() {
        for ext in ["m4b", "m4a", "mp3", "aac", "flac", "zip", "M4B", "MP3"] {
            XCTAssertTrue(ShareImportAllowlist.allows(pathExtension: ext), ext)
        }
        for ext in ["jpg", "pdf", "png", "mov", "aa", "aax", "wav", "aiff"] {
            XCTAssertFalse(ShareImportAllowlist.allows(pathExtension: ext), ext)
            XCTAssertFalse(
                ShareImportAllowlist.allowsFile(typeIdentifiers: ["public.data"], pathExtension: ext),
                ext
            )
        }
    }

    func testTypeIdentifiersMatchTheSharePredicate() {
        for identifier in ShareImportAllowlist.typeIdentifiers {
            XCTAssertTrue(ShareImportAllowlist.allows(typeIdentifier: identifier), identifier)
        }
        XCTAssertTrue(ShareImportAllowlist.allows(typeIdentifier: "public.mpeg-4-audio"))
        XCTAssertTrue(ShareImportAllowlist.allows(typeIdentifier: "com.apple.m4b-audio"))
        for identifier in ["public.jpeg", "public.png", "com.adobe.pdf", "public.movie", "public.image", "public.audio", "public.data", "public.item"] {
            XCTAssertFalse(ShareImportAllowlist.allows(typeIdentifier: identifier), identifier)
        }
    }

    func testFileURLNeedsAnAllowedTypeOrExtension() {
        XCTAssertTrue(ShareImportAllowlist.allowsFile(typeIdentifiers: ["public.file-url"], pathExtension: "m4b"))
        XCTAssertTrue(ShareImportAllowlist.allowsFile(typeIdentifiers: ["public.mp3"], pathExtension: "dat"))
        XCTAssertFalse(ShareImportAllowlist.allowsFile(typeIdentifiers: ["public.audio"], pathExtension: "wav"))
        XCTAssertFalse(ShareImportAllowlist.allowsFile(typeIdentifiers: ["public.movie"], pathExtension: "mov"))
        XCTAssertEqual(ShareImportAllowlist.maxAttachmentCount, 20)
        XCTAssertEqual(ShareImportAllowlist.typeIdentifiers.count, 6)
    }

    func testSharePlistPredicateListsTheSixTypes() throws {
        let plist = try loadPlist("ChapterlineShare/Info.plist")
        let extensionInfo = try XCTUnwrap(plist["NSExtension"] as? [String: Any])
        let attributes = try XCTUnwrap(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let rule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? String)
        for identifier in ShareImportAllowlist.typeIdentifiers {
            XCTAssertTrue(rule.contains(identifier), identifier)
        }
        XCTAssertFalse(rule.contains("SupportsFileWithMaxCount"))
        XCTAssertFalse(rule.contains("SupportsAttachmentsWithMaxCount"))
        XCTAssertFalse(rule.contains("TRUEPREDICATE"))
        XCTAssertFalse(rule.contains("\"public.audio\""))
        XCTAssertFalse(rule.contains("public.image"))
        XCTAssertFalse(rule.contains("public.data"))
        XCTAssertFalse(rule.contains("public.movie"))
        XCTAssertFalse(rule.contains("public.content"))
        XCTAssertFalse(rule.contains("public.item"))
    }

    func testShareControllerDoesNotInventAudiobooks() throws {
        let source = try String(contentsOf: repoFile("ChapterlineShare/ShareViewController.swift"), encoding: .utf8)
        XCTAssertFalse(source.contains("\"share-"))
        XCTAssertFalse(source.contains("UUID().uuidString"))
        XCTAssertFalse(source.contains("audiovisualContent"))
        XCTAssertFalse(source.contains("UTType.data"))
        XCTAssertTrue(source.contains("NSExtensionActivationRule"))
        XCTAssertTrue(source.contains("ShareImportAllowlist"))
    }

    func testDocumentTypesAreAlternateAndOmitPublicAudio() throws {
        let plist = try loadPlist("Chapterline-Info.plist")
        let types = try XCTUnwrap(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        let audiobook = try XCTUnwrap(types.first)
        XCTAssertEqual(audiobook["CFBundleTypeRole"] as? String, "Viewer")
        XCTAssertEqual(audiobook["LSHandlerRank"] as? String, "Alternate")
        XCTAssertNotEqual(audiobook["LSHandlerRank"] as? String, "Owner")
        XCTAssertNotEqual(audiobook["LSHandlerRank"] as? String, "Default")
        let content = try XCTUnwrap(audiobook["LSItemContentTypes"] as? [String])
        XCTAssertEqual(content, [
            "com.apple.m4b-audio",
            "public.mpeg-4-audio",
            "public.mp3",
            "public.aac-audio",
            "org.xiph.flac",
            "public.zip-archive"
        ])
        XCTAssertFalse(content.contains("public.audio"))
    }

    private func loadPlist(_ relativePath: String) throws -> [String: Any] {
        let url = repoFile(relativePath)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }

    private func repoFile(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
