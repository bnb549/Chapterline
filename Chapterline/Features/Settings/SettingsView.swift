import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PlayerController.self) private var player
    @Environment(ListeningStatsStore.self) private var stats
    @State private var confirmDeleteStats = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.pageBackground(oled: settings.usesTrueBlack).ignoresSafeArea()
                Form {
                    playbackSection
                    rewindSection
                    appearanceSection
                    statsSection
                    carPlaySection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .toolbarBackground(settings.usesTrueBlack ? Color.black : Color.clear, for: .navigationBar)
            .toolbarBackground(settings.usesTrueBlack ? .visible : .automatic, for: .navigationBar)
            .confirmationDialog(
                "Delete all listening stats?",
                isPresented: $confirmDeleteStats,
                titleVisibility: .visible
            ) {
                Button("Delete All Stats", role: .destructive) {
                    stats.deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sessions and totals on this device will be removed. Books and progress stay.")
            }
        }
    }

    private var playbackSection: some View {
        Section("Playback") {
            Picker("Skip back", selection: Binding(
                get: { settings.skipBack },
                set: { settings.skipBack = $0; NowPlayingBridge.shared.applySkipIntervals() }
            )) {
                ForEach(SkipInterval.allCases, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            .accessibilityLabel("Default skip back interval")

            Picker("Skip forward", selection: Binding(
                get: { settings.skipForward },
                set: { settings.skipForward = $0; NowPlayingBridge.shared.applySkipIntervals() }
            )) {
                ForEach(SkipInterval.allCases, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
            }
            .accessibilityLabel("Default skip forward interval")

            VStack(alignment: .leading) {
                Text("Default speed \(settings.defaultSpeed, specifier: "%.1f")×")
                Slider(value: Binding(
                    get: { settings.defaultSpeed },
                    set: { settings.defaultSpeed = ($0 * 10).rounded() / 10 }
                ), in: 0.5...3.0, step: 0.1)
                .accessibilityLabel("Default playback speed")
            }

            VStack(alignment: .leading) {
                Text("Voice boost \(settings.boost, specifier: "%.2f")×")
                Slider(value: Binding(
                    get: { settings.boost },
                    set: { value in
                        settings.boost = value
                        Task { await player.setBoost(value) }
                    }
                ), in: 1.0...2.0, step: 0.05)
                .accessibilityLabel("Voice boost")
            }

            VStack(alignment: .leading) {
                Text("Sleep fade \(Int(settings.sleepFadeSeconds))s")
                Slider(value: Binding(
                    get: { settings.sleepFadeSeconds },
                    set: { settings.sleepFadeSeconds = $0 }
                ), in: 5...20, step: 1)
                .accessibilityLabel("Sleep fade duration")
            }
        }
    }

    private var rewindSection: some View {
        Section("Smart rewind") {
            Toggle("Rewind on resume", isOn: Binding(
                get: { settings.smartRewindEnabled },
                set: { settings.smartRewindEnabled = $0 }
            ))
            .accessibilityLabel("Smart rewind on resume")
            Toggle("Shake to extend sleep timer", isOn: Binding(
                get: { settings.shakeToExtendSleep },
                set: {
                    settings.shakeToExtendSleep = $0
                    player.shakeToExtend = $0
                }
            ))
            Text("After a short pause Chapterline skips back about 3 seconds. After a long gap it skips back up to 30 seconds, without crossing a chapter boundary.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { settings.appearance },
                set: { settings.appearance = $0 }
            )) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .accessibilityLabel("Appearance")
            Toggle("Hide remaining time", isOn: Binding(
                get: { settings.hideRemainingTime },
                set: { settings.hideRemainingTime = $0 }
            ))
            .accessibilityLabel("Hide remaining time")
            Text("For spoiler-sensitive listening. Progress percent still shows.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var statsSection: some View {
        Section("Listening stats") {
            Toggle("Track listening stats", isOn: Binding(
                get: { settings.trackListeningStats },
                set: { enabled in
                    settings.trackListeningStats = enabled
                    if !enabled {
                        stats.discardOpenSession()
                    }
                }
            ))
            .accessibilityLabel("Track listening stats")
            Text("Hours stay on this device. Seeking does not inflate time. Sessions under 15 seconds are ignored.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            ShareLink(
                item: stats.exportFileURL(),
                preview: SharePreview("Chapterline Stats")
            ) {
                Label("Export JSON", systemImage: "square.and.arrow.up")
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Export listening stats as JSON")
            .disabled(stats.allTimeSessionCount == 0)

            Button("Delete all stats", role: .destructive) {
                confirmDeleteStats = true
            }
            .frame(minHeight: 44, alignment: .leading)
            .accessibilityLabel("Delete all listening stats")
            .disabled(stats.allTimeSessionCount == 0 && !stats.hasOpenSession)
        }
    }

    private var carPlaySection: some View {
        Section("CarPlay") {
            Toggle("Show player on launch", isOn: Binding(
                get: { settings.carPlayOpenPlayerOnLaunch },
                set: { settings.carPlayOpenPlayerOnLaunch = $0 }
            ))
            .accessibilityLabel("Show player on CarPlay launch")
            Text("Now Playing always works. Browsing the library in a car needs Apple’s CarPlay Audio entitlement.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Chapterline")
            LabeledContent("Kind", value: "Local, DRM-free, offline first")
            Text("No account. No store. No ads. Files stay on this device. Audible .aa / .aax is not supported.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
