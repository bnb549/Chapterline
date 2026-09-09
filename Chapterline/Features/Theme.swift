import SwiftUI
import UIKit

enum Theme {
    static let background = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
            : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    })
    static let chrome = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
            : UIColor.white
    })
    static let elevated = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1)
            : UIColor(red: 0.90, green: 0.90, blue: 0.93, alpha: 1)
    })
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(uiColor: .tertiaryLabel)
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.08)
    })
    static let fill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.12)
            : UIColor.black.withAlphaComponent(0.08)
    })
    static let fillStrong = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.55)
            : UIColor.black.withAlphaComponent(0.35)
    })
    static let playFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : UIColor(white: 0.12, alpha: 1)
    })
    static let playIcon = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let coverShadow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black.withAlphaComponent(0.45)
            : UIColor.black.withAlphaComponent(0.16)
    })
    static let oledBackground = Color.black
    static let oledChrome = Color(red: 0.08, green: 0.08, blue: 0.08)

    static func pageBackground(oled: Bool) -> Color {
        oled ? oledBackground : background
    }

    static func chromeBackground(oled: Bool) -> Color {
        oled ? oledChrome : chrome
    }
}

struct CoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 10

    var body: some View {
        Image(uiImage: ArtworkStore.image(for: book))
            .resizable()
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(Theme.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

struct RemainingLabel: View {
    let book: Book
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if settings.hideRemainingTime {
            Text(book.isFinished ? "Finished" : "\(Int((book.progress * 100).rounded()))%")
        } else if book.isFinished {
            Text("Finished")
        } else {
            Text(TimeMath.formatRemaining(duration: book.duration, position: book.position, rate: book.playbackRate))
        }
    }
}
