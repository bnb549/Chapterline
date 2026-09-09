import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerController.self) private var player

    @State private var search = ""
    @State private var showImporter = false
    @State private var bookToDelete: Book?
    @State private var showFolderSheet = false
    @State private var path = NavigationPath()

    var selectedFolder: Folder? {
        guard let id = library.selectedFolderID else { return nil }
        return library.folders.first { $0.persistentModelID == id }
    }

    var visibleBooks: [Book] {
        library.filteredBooks(search: search, folder: selectedFolder, sort: settings.librarySort)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.pageBackground(oled: settings.usesTrueBlack).ignoresSafeArea()
                content
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(settings.usesTrueBlack ? Color.black : Color.clear, for: .navigationBar)
            .toolbarBackground(settings.usesTrueBlack ? .visible : .automatic, for: .navigationBar)
            .searchable(text: $search, prompt: "Title, author, filename")
            .toolbar { toolbar }
            .navigationDestination(for: UUID.self) { id in
                if let book = library.book(id: id) {
                    BookPlayerView(bookID: id)
                        .onAppear {
                            Task { await player.load(book: book) }
                        }
                }
            }
            .sheet(isPresented: $showImporter) {
                DocumentImporter { urls in
                    showImporter = false
                    Task { await library.handleIncomingURLs(urls) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showFolderSheet) {
                FolderManagerView()
            }
            .confirmationDialog(
                "Combine into one book?",
                isPresented: Binding(
                    get: { library.pendingCombine != nil },
                    set: { if !$0 { library.pendingCombine = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Combine into one book") {
                    Task { await library.resolvePendingCombine(true) }
                }
                Button("Import as separate books") {
                    Task { await library.resolvePendingCombine(false) }
                }
                Button("Cancel", role: .cancel) {
                    library.pendingCombine = nil
                }
            } message: {
                Text("You selected several files. Combining plays them gaplessly as one book.")
            }
            .alert("Couldn’t import", isPresented: Binding(
                get: { library.importError != nil },
                set: { if !$0 { library.importError = nil } }
            )) {
                Button("OK", role: .cancel) { library.importError = nil }
            } message: {
                Text(library.importError ?? "")
            }
            .confirmationDialog("Delete this book?", isPresented: Binding(
                get: { bookToDelete != nil },
                set: { if !$0 { bookToDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        if player.loadedBookID == book.id {
                            Task { await player.pause() }
                        }
                        library.delete(book)
                    }
                    bookToDelete = nil
                }
                Button("Cancel", role: .cancel) { bookToDelete = nil }
            } message: {
                Text("The sandbox copy and its progress will be removed.")
            }
            .overlay(alignment: .bottom) {
                if let progress = library.importProgress {
                    ImportBanner(progress: progress)
                        .padding()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if library.books.isEmpty && search.isEmpty && selectedFolder == nil {
            EmptyLibraryView { showImporter = true }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if search.isEmpty, selectedFolder == nil, let current = library.continueListening {
                        ContinueListeningHeader(book: current) {
                            path.append(current.id)
                        }
                        .padding(.horizontal)
                    }
                    folderChips
                    if visibleBooks.isEmpty {
                        ContentUnavailableView.search(text: search)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if settings.libraryLayout == .grid {
                        grid
                    } else {
                        list
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var folderChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", selected: selectedFolder == nil) {
                    library.selectedFolderID = nil
                }
                ForEach(library.folders, id: \.persistentModelID) { folder in
                    chip(title: folder.name, selected: selectedFolder?.persistentModelID == folder.persistentModelID) {
                        library.selectedFolderID = folder.persistentModelID
                    }
                }
            }
            .padding(.horizontal)
        }
        .accessibilityLabel("Folders")
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor.opacity(0.28) : Theme.chromeBackground(oled: settings.usesTrueBlack), in: Capsule())
                .foregroundStyle(selected ? Color.accentColor : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 18) {
            ForEach(visibleBooks, id: \.persistentModelID) { book in
                Button {
                    path.append(book.id)
                } label: {
                    LibraryGridItem(book: book)
                }
                .buttonStyle(.plain)
                .contextMenu { bookMenu(book) }
            }
        }
        .padding(.horizontal)
    }

    private var list: some View {
        LazyVStack(spacing: 0) {
            ForEach(visibleBooks, id: \.persistentModelID) { book in
                Button {
                    path.append(book.id)
                } label: {
                    LibraryListItem(book: book)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        bookToDelete = book
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        library.markFinished(book, finished: !book.isFinished)
                    } label: {
                        Label(book.isFinished ? "Not Finished" : "Finished", systemImage: "checkmark.circle")
                    }
                    .tint(.orange)
                }
                .contextMenu { bookMenu(book) }
                Divider().overlay(Theme.hairline)
            }
        }
        .padding(.horizontal)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Sort", selection: Binding(
                    get: { settings.librarySort },
                    set: { settings.librarySort = $0 }
                )) {
                    ForEach(LibrarySort.allCases, id: \.self) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
                Button("Folders") { showFolderSheet = true }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort and folders")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                settings.libraryLayout = settings.libraryLayout == .grid ? .list : .grid
            } label: {
                Image(systemName: settings.libraryLayout == .grid ? "list.bullet" : "square.grid.2x2")
            }
            .accessibilityLabel(settings.libraryLayout == .grid ? "Show list" : "Show grid")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Import from Files")
        }
    }

    @ViewBuilder
    private func bookMenu(_ book: Book) -> some View {
        Button {
            library.markFinished(book, finished: !book.isFinished)
        } label: {
            Label(book.isFinished ? "Mark Unfinished" : "Mark Finished", systemImage: "checkmark.circle")
        }
        Menu("Move to Folder") {
            Button("None") { library.move(book, to: nil) }
            ForEach(library.folders, id: \.persistentModelID) { folder in
                Button(folder.name) { library.move(book, to: folder) }
            }
        }
        Button(role: .destructive) {
            bookToDelete = book
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct LibraryGridItem: View {
    let book: Book
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                CoverView(book: book, cornerRadius: 12)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: Theme.coverShadow, radius: 8, y: 4)
                ProgressRing(progress: book.progress)
                    .frame(width: 28, height: 28)
                    .padding(8)
            }
            Text(book.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text(book.author)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            RemainingLabel(book: book)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let remaining = settings.hideRemainingTime
            ? "\(Int((book.progress * 100).rounded())) percent"
            : TimeMath.formatRemaining(duration: book.duration, position: book.position, rate: book.playbackRate)
        return "\(book.title), \(book.author), \(remaining)"
    }
}

struct LibraryListItem: View {
    let book: Book
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 14) {
            CoverView(book: book, cornerRadius: 8)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(book.author)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                RemainingLabel(book: book)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            ProgressRing(progress: book.progress)
                .frame(width: 26, height: 26)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title), \(book.author)")
        .accessibilityValue(settings.hideRemainingTime
            ? "\(Int((book.progress * 100).rounded())) percent"
            : TimeMath.formatRemaining(duration: book.duration, position: book.position, rate: book.playbackRate))
    }
}

struct ContinueListeningHeader: View {
    let book: Book
    var action: () -> Void
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CoverView(book: book, cornerRadius: 8)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue Listening")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let chapter = book.currentChapter {
                        Text(chapter.title)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    RemainingLabel(book: book)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())
            }
            .padding(14)
            .background(Theme.chromeBackground(oled: settings.usesTrueBlack), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue listening to \(book.title)")
        .accessibilityHint("Opens the player")
    }
}

struct EmptyLibraryView: View {
    var importAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No books yet", systemImage: "books.vertical")
        } description: {
            Text("AirDrop an .m4b, pick one from Files, or share a file into Chapterline. DRM-free only — Audible .aa / .aax won’t import.")
        } actions: {
            Button("Import from Files", action: importAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

struct ImportBanner: View {
    let progress: ImportProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(progress.message)
                .font(.subheadline.weight(.semibold))
            ProgressView(value: progress.fraction)
                .tint(Color.accentColor)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Importing, \(Int(progress.fraction * 100)) percent")
    }
}

struct FolderManagerView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(library.folders, id: \.persistentModelID) { folder in
                    Text(folder.name)
                        .swipeActions {
                            Button(role: .destructive) {
                                library.deleteFolder(folder)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                HStack {
                    TextField("New folder", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        library.addFolder(named: name)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.pageBackground(oled: settings.usesTrueBlack))
            .navigationTitle("Folders")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.pageBackground(oled: settings.usesTrueBlack))
    }
}

#if DEBUG
#Preview("Library") {
    let library = PreviewSupport.library()
    return LibraryView()
        .environment(library)
        .environment(SettingsStore.shared)
        .environment(PlayerController())
        .preferredColorScheme(.dark)
}
#endif
