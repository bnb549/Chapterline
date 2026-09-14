import SwiftUI

struct HeatmapLegend: View {
    private var items: [(label: String, wall: TimeInterval)] {
        [
            ("None", 0),
            ("15m", 60),
            ("45m", 15 * 60),
            ("90m", 45 * 60),
            ("1.5h+", 90 * 60)
        ]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            wrapped
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heatmap key. None, under 15 minutes, under 45 minutes, under 90 minutes, 1.5 hours or more.")
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Text("·")
                        .foregroundStyle(Theme.textTertiary)
                }
                swatch(item.wall)
                Text(item.label)
            }
        }
        .lineLimit(1)
    }

    private var wrapped: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    swatch(item.wall)
                    Text(item.label)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(items.suffix(2).enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    swatch(item.wall)
                    Text(item.label)
                }
            }
        }
    }

    private func swatch(_ wall: TimeInterval) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(HeatmapPaint.color(for: wall))
            .frame(width: 8, height: 8)
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            }
    }
}
