import SwiftUI

struct ChapterListSheet: View {
    let book: Book
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(book.sortedChapters, id: \.persistentModelID) { chapter in
                    Button {
                        Task {
                            await player.seek(to: chapter.start)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .foregroundStyle(Theme.textPrimary)
                                Text(TimeMath.format(duration: chapter.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if isCurrent(chapter) {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Current chapter")
                            }
                        }
                    }
                    .listRowBackground(isCurrent(chapter) ? Color.accentColor.opacity(0.18) : Theme.chromeBackground(oled: settings.usesTrueBlack))
                    .accessibilityLabel(chapter.title)
                    .accessibilityValue(isCurrent(chapter) ? "Current, \(TimeMath.format(duration: chapter.start))" : TimeMath.format(duration: chapter.start))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .navigationTitle("Chapters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }

    private func isCurrent(_ chapter: Chapter) -> Bool {
        let current = player.snapshot.chapterStart
        return abs(current - chapter.start) < 0.5
    }
}

struct BookmarkSheet: View {
    let book: Book
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Optional note", text: $note)
                    Button {
                        let snap = player.snapshot
                        library.addBookmark(
                            on: book,
                            position: snap.position,
                            chapterStart: snap.chapterStart,
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
                        )
                        note = ""
                    } label: {
                        Label("Drop bookmark at \(TimeMath.format(duration: player.snapshot.position))", systemImage: "bookmark.fill")
                    }
                    .accessibilityLabel("Add bookmark at current time")
                }
                Section("Bookmarks") {
                    if book.sortedBookmarks.isEmpty {
                        Text("No bookmarks yet")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(book.sortedBookmarks, id: \.persistentModelID) { bookmark in
                        Button {
                            Task {
                                await player.seek(to: bookmark.position)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TimeMath.format(duration: bookmark.position))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                if let note = bookmark.note, !note.isEmpty {
                                    Text(note).foregroundStyle(Theme.textSecondary)
                                }
                                Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .accessibilityLabel("Bookmark at \(TimeMath.format(duration: bookmark.position))")
                        .swipeActions {
                            Button(role: .destructive) {
                                library.deleteBookmark(bookmark)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}

struct SleepTimerSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var customMinutes = 20.0

    var body: some View {
        NavigationStack {
            List {
                if let remaining = player.snapshot.sleepRemaining {
                    Section("Running") {
                        Text("Ends in \(TimeMath.format(duration: remaining))")
                        if player.snapshot.sleepFading {
                            Text("Fading out")
                                .foregroundStyle(Color.accentColor)
                        }
                        Button("Cancel timer", role: .destructive) {
                            Task { await player.cancelSleep() }
                        }
                    }
                }
                Section("Presets") {
                    ForEach([5, 15, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) minutes") {
                            Task {
                                await player.startSleep(minutes: Double(minutes))
                                dismiss()
                            }
                        }
                        .accessibilityLabel("Sleep in \(minutes) minutes")
                    }
                    Button("End of chapter") {
                        Task {
                            await player.startSleepEndOfChapter()
                            dismiss()
                        }
                    }
                    .accessibilityLabel("Sleep at end of chapter")
                }
                Section("Custom") {
                    Stepper("\(Int(customMinutes)) minutes", value: $customMinutes, in: 1...180, step: 1)
                    Button("Start custom") {
                        Task {
                            await player.startSleep(minutes: customMinutes)
                            dismiss()
                        }
                    }
                }
                Section {
                    Text("The last 10 seconds fade out. Shake the phone to add 15 minutes.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .navigationTitle("Sleep timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}

struct SpeedSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("\(player.snapshot.rate, specifier: "%.1f")×")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Speed \(String(format: "%.1f", player.snapshot.rate)) times")
                Slider(
                    value: Binding(
                        get: { player.snapshot.rate },
                        set: { newValue in
                            Task { await player.setRate(newValue) }
                        }
                    ),
                    in: 0.5...3.0,
                    step: 0.1
                )
                .tint(Color.accentColor)
                .padding(.horizontal)
                .accessibilityLabel("Playback speed")
                HStack {
                    ForEach([0.8, 1.0, 1.2, 1.5, 1.6, 2.0], id: \.self) { rate in
                        Button("\(rate, specifier: "%.1f")×") {
                            Task { await player.setRate(rate) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Spacer()
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .navigationTitle("Speed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}

struct BoostSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Voice boost")
                    .font(.title2.weight(.semibold))
                Text("Raises dialogue without re-encoding. Peaks are clipped so it stays safe for headphones.")
                    .foregroundStyle(Theme.textSecondary)
                Slider(
                    value: Binding(
                        get: { settings.boost },
                        set: { value in
                            settings.boost = value
                            Task { await player.setBoost(value) }
                        }
                    ),
                    in: 1.0...2.0,
                    step: 0.05
                )
                .tint(Color.accentColor)
                .accessibilityLabel("Voice boost")
                .accessibilityValue(String(format: "%.2f", settings.boost))
                Text("\(settings.boost, specifier: "%.2f")×")
                    .font(.headline.monospacedDigit())
                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}

struct EditMetadataView: View {
    let book: Book
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var narrator: String = ""
    @State private var showPhoto = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author)
                    TextField("Narrator", text: $narrator)
                }
                Section("Artwork") {
                    CoverView(book: book, cornerRadius: 12)
                        .frame(width: 120, height: 120)
                    Button("Choose override…") { showPhoto = true }
                    Text("Override is stored separately. Embedded art is never overwritten.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .navigationTitle("Edit book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        library.rename(book, title: title, author: author, narrator: narrator)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showPhoto) {
                PhotoImporter { data in
                    showPhoto = false
                    if let data {
                        ArtworkStore.writeOverride(data, book: book)
                        library.save()
                    }
                }
                .ignoresSafeArea()
            }
            .onAppear {
                title = book.title
                author = book.author
                narrator = book.narrator ?? ""
            }
        }
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}
