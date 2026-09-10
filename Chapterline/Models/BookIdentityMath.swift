import CryptoKit
import Foundation

struct BookFingerprint: Equatable, Sendable {
    var identityKey: String
    var title: String
    var author: String
    var duration: TimeInterval
    var totalByteSize: Int64
    var fileCount: Int
    var sourceSignature: String
    var probeHash: String?
    var filenames: [String]
}

struct BookIdentityCandidate: Equatable, Sendable {
    var bookID: UUID
    var identityKey: String?
    var title: String
    var author: String
    var duration: TimeInterval?
    var totalByteSize: Int64?
    var sourceSignature: String?
    var probeHash: String?
    var lastSeenAt: Date
    var sessionCount: Int
    var finishedAt: Date?
}

struct OrphanSessionInput: Equatable, Sendable {
    var bookID: UUID
    var identityKey: String?
    var bookTitle: String
    var author: String
    var endedAt: Date
    var endReason: SessionEndReason
}

struct BookIdentityResolution: Equatable, Sendable {
    var bookID: UUID
    var reused: Bool
    var finishedAt: Date?
}

enum BookIdentityMath: Sendable {
    nonisolated static let durationTolerance: TimeInterval = 2
    nonisolated static let probeChunkSize = 256 * 1024

    nonisolated static let genericFilenameStems: Set<String> = [
        "audio", "untitled", "unknown", "track", "file", "book", "audiobook", "title", "chapter"
    ]

    nonisolated static func normalizeTitle(_ title: String) -> String {
        normalizeWhitespaceAndCase(title)
    }

    nonisolated static func normalizeAuthor(_ author: String) -> String {
        let normalized = normalizeWhitespaceAndCase(author)
        return normalized == "unknown author" ? "" : normalized
    }

    nonisolated static func normalizeWhitespaceAndCase(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    nonisolated static func stripCombinePrefix(_ filename: String) -> String {
        let chars = Array(filename)
        guard chars.count >= 4 else { return filename }
        guard chars[0].isNumber, chars[1].isNumber, chars[2].isNumber, chars[3] == "-" else {
            return filename
        }
        return String(chars.dropFirst(4))
    }

    nonisolated static func normalizedFilename(_ filename: String) -> String {
        normalizeWhitespaceAndCase(stripCombinePrefix(filename))
    }

    nonisolated static func filenameStem(_ filename: String) -> String {
        let normalized = normalizedFilename(filename)
        return (normalized as NSString).deletingPathExtension
    }

    nonisolated static func sourceSignature(filenames: [String]) -> String {
        filenames
            .map(normalizedFilename)
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\n")
    }

    nonisolated static func isGenericStem(_ stem: String) -> Bool {
        genericFilenameStems.contains(normalizeWhitespaceAndCase(stem))
    }

    nonisolated static func isGenericSignature(_ signature: String) -> Bool {
        let parts = signature.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 1 else { return false }
        return isGenericStem(filenameStem(parts[0]))
    }

    nonisolated static func sourceSignaturesCompatible(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let left = lhs.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let right = rhs.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard left.count == 1, right.count == 1 else { return false }
        return filenameStem(left[0]) == filenameStem(right[0])
    }

    nonisolated static func identityKey(
        title: String,
        author: String,
        duration: TimeInterval,
        totalByteSize: Int64,
        fileCount: Int,
        sourceSignature: String,
        probeHash: String? = nil
    ) -> String {
        let roundedDuration = Int(duration.rounded())
        var canonical = [
            "v1",
            normalizeTitle(title),
            normalizeAuthor(author),
            String(roundedDuration),
            String(totalByteSize),
            String(fileCount),
            sourceSignature
        ].joined(separator: "\u{1e}")
        if let probeHash, !probeHash.isEmpty {
            canonical += "\u{1e}\(probeHash)"
        }
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func fingerprint(
        title: String,
        author: String,
        duration: TimeInterval,
        totalByteSize: Int64,
        filenames: [String],
        probeHash: String? = nil
    ) -> BookFingerprint {
        let signature = sourceSignature(filenames: filenames)
        let key = identityKey(
            title: title,
            author: author,
            duration: duration,
            totalByteSize: totalByteSize,
            fileCount: filenames.count,
            sourceSignature: signature,
            probeHash: probeHash
        )
        return BookFingerprint(
            identityKey: key,
            title: title,
            author: author,
            duration: duration,
            totalByteSize: totalByteSize,
            fileCount: filenames.count,
            sourceSignature: signature,
            probeHash: probeHash,
            filenames: filenames
        )
    }

    nonisolated static func makeFingerprint(
        title: String,
        author: String,
        duration: TimeInterval,
        fileURLs: [URL],
        filenames: [String],
        includeProbe: Bool = true
    ) -> BookFingerprint {
        let total = fileURLs.reduce(Int64(0)) { $0 + byteSize(of: $1) }
        let probe = includeProbe ? fileURLs.first.flatMap(probeHash(of:)) : nil
        return fingerprint(
            title: title,
            author: author,
            duration: duration,
            totalByteSize: total,
            filenames: filenames,
            probeHash: probe
        )
    }

    nonisolated static func byteSize(of url: URL) -> Int64 {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            return Int64(size)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// First 256 KB + last 256 KB + file size. Never reads the whole audiobook.
    nonisolated static func probeHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        do {
            try handle.seek(toOffset: 0)
        } catch {
            return nil
        }
        let chunk = probeChunkSize
        let headCount = min(chunk, Int(min(size, UInt64(Int.max))))
        let head = (try? handle.read(upToCount: headCount)) ?? Data()
        var tail = Data()
        if size > UInt64(chunk) {
            let offset = size - UInt64(chunk)
            do {
                try handle.seek(toOffset: offset)
                tail = (try? handle.read(upToCount: chunk)) ?? Data()
            } catch {
                return nil
            }
        }
        var data = head
        data.append(tail)
        var sizeBE = size.bigEndian
        withUnsafeBytes(of: &sizeBE) { data.append(contentsOf: $0) }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func titlesMatch(incoming: BookFingerprint, candidate: BookIdentityCandidate) -> Bool {
        let left = normalizeTitle(incoming.title)
        let right = normalizeTitle(candidate.title)
        if left == right { return true }
        guard left.isEmpty || right.isEmpty else { return false }
        let leftStem = incoming.filenames.first.map(filenameStem) ?? primaryStem(from: incoming.sourceSignature)
        let rightStem = primaryStem(from: candidate.sourceSignature)
        guard !leftStem.isEmpty, leftStem == rightStem else { return false }
        return true
    }

    nonisolated static func fuzzyMatch(incoming: BookFingerprint, candidate: BookIdentityCandidate) -> Bool {
        guard let candidateDuration = candidate.duration else { return false }
        let incomingRounded = incoming.duration.rounded()
        let candidateRounded = candidateDuration.rounded()
        guard abs(incomingRounded - candidateRounded) <= durationTolerance else { return false }

        guard titlesMatch(incoming: incoming, candidate: candidate) else { return false }

        let leftAuthor = normalizeAuthor(incoming.author)
        let rightAuthor = normalizeAuthor(candidate.author)
        let authorsEqual = leftAuthor == rightAuthor
        let authorMissingOnOneSide = leftAuthor.isEmpty || rightAuthor.isEmpty
        guard authorsEqual || authorMissingOnOneSide else { return false }

        if let candidateSize = candidate.totalByteSize {
            guard candidateSize == incoming.totalByteSize else { return false }
        }

        if let candidateSignature = candidate.sourceSignature, !candidateSignature.isEmpty {
            guard sourceSignaturesCompatible(incoming.sourceSignature, candidateSignature) else { return false }
        }

        if let incomingProbe = incoming.probeHash, !incomingProbe.isEmpty,
           let candidateProbe = candidate.probeHash, !candidateProbe.isEmpty {
            guard incomingProbe == candidateProbe else { return false }
        }

        if !authorsEqual, authorMissingOnOneSide {
            let incomingGeneric = isGenericSignature(incoming.sourceSignature)
            let candidateGeneric = candidate.sourceSignature.map(isGenericSignature) ?? incomingGeneric
            if incomingGeneric || candidateGeneric {
                return false
            }
            if incoming.sourceSignature.isEmpty {
                return false
            }
        }

        return true
    }

    nonisolated static func orphanCandidates(
        sessions: [OrphanSessionInput],
        liveBookIDs: Set<UUID>
    ) -> [BookIdentityCandidate] {
        struct Group {
            var bookID: UUID
            var identityKey: String?
            var title: String
            var author: String
            var lastSeenAt: Date
            var sessionCount: Int
            var finishedAt: Date?
        }
        var grouped: [UUID: Group] = [:]
        for session in sessions where !liveBookIDs.contains(session.bookID) {
            var group = grouped[session.bookID] ?? Group(
                bookID: session.bookID,
                identityKey: session.identityKey,
                title: session.bookTitle,
                author: session.author,
                lastSeenAt: session.endedAt,
                sessionCount: 0,
                finishedAt: nil
            )
            group.sessionCount += 1
            if session.endedAt >= group.lastSeenAt {
                group.lastSeenAt = session.endedAt
                group.title = session.bookTitle
                group.author = session.author
            }
            if group.identityKey == nil {
                group.identityKey = session.identityKey
            }
            if session.endReason == .finished {
                group.finishedAt = group.finishedAt ?? session.endedAt
            }
            grouped[session.bookID] = group
        }
        return grouped.values.map {
            BookIdentityCandidate(
                bookID: $0.bookID,
                identityKey: $0.identityKey,
                title: $0.title,
                author: $0.author,
                duration: nil,
                totalByteSize: nil,
                sourceSignature: nil,
                probeHash: nil,
                lastSeenAt: $0.lastSeenAt,
                sessionCount: $0.sessionCount,
                finishedAt: $0.finishedAt
            )
        }
    }

    nonisolated static func resolve(
        fingerprint: BookFingerprint,
        liveBookIDs: Set<UUID>,
        identities: [BookIdentityCandidate],
        orphans: [BookIdentityCandidate],
        stagingID: UUID
    ) -> BookIdentityResolution {
        let merged = mergeCandidates(identities: identities, orphans: orphans, liveBookIDs: liveBookIDs)

        let exact = merged.filter { candidate in
            guard let key = candidate.identityKey, !key.isEmpty else { return false }
            return key == fingerprint.identityKey
        }
        // Identical keys on two bookIDs are ambiguous — never steal hours from "Untitled".
        if exact.count == 1 {
            return .init(bookID: exact[0].bookID, reused: true, finishedAt: exact[0].finishedAt)
        }
        if exact.count > 1 {
            return .init(bookID: stagingID, reused: false, finishedAt: nil)
        }

        let fuzzy = merged.filter { fuzzyMatch(incoming: fingerprint, candidate: $0) }
        if let chosen = uniqueChoice(fuzzy) {
            return .init(bookID: chosen.bookID, reused: true, finishedAt: chosen.finishedAt)
        }
        return .init(bookID: stagingID, reused: false, finishedAt: nil)
    }

    nonisolated static func mergeCandidates(
        identities: [BookIdentityCandidate],
        orphans: [BookIdentityCandidate],
        liveBookIDs: Set<UUID>
    ) -> [BookIdentityCandidate] {
        var byID: [UUID: BookIdentityCandidate] = [:]
        for identity in identities where !liveBookIDs.contains(identity.bookID) {
            byID[identity.bookID] = identity
        }
        for orphan in orphans where !liveBookIDs.contains(orphan.bookID) {
            if var existing = byID[orphan.bookID] {
                existing.sessionCount += orphan.sessionCount
                if orphan.lastSeenAt > existing.lastSeenAt {
                    existing.lastSeenAt = orphan.lastSeenAt
                }
                if existing.identityKey == nil {
                    existing.identityKey = orphan.identityKey
                }
                if existing.finishedAt == nil {
                    existing.finishedAt = orphan.finishedAt
                }
                byID[orphan.bookID] = existing
            } else {
                byID[orphan.bookID] = orphan
            }
        }
        return Array(byID.values)
    }

    /// One match, or a unique winner by session count then recency. Ties stay unused.
    nonisolated static func uniqueChoice(_ candidates: [BookIdentityCandidate]) -> BookIdentityCandidate? {
        if candidates.isEmpty { return nil }
        if candidates.count == 1 { return candidates[0] }

        let bestCount = candidates.map(\.sessionCount).max() ?? 0
        let bySessions = candidates.filter { $0.sessionCount == bestCount }
        if bySessions.count == 1 { return bySessions[0] }

        let bestSeen = bySessions.map(\.lastSeenAt).max() ?? .distantPast
        let byRecency = bySessions.filter { $0.lastSeenAt == bestSeen }
        if byRecency.count == 1 { return byRecency[0] }
        return nil
    }

    private nonisolated static func primaryStem(from signature: String?) -> String {
        guard let signature, !signature.isEmpty else { return "" }
        guard let first = signature.split(separator: "\n", omittingEmptySubsequences: true).first else {
            return ""
        }
        return filenameStem(String(first))
    }
}
