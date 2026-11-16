import SwiftUI

/// The segmented bar from the design: one coloured piece per category, sized by its share,
/// with a legend underneath.
struct StorageBar: View {
    struct Segment: Identifiable {
        let label: String
        let value: Int64
        let color: Color
        var id: String { label }
    }

    let segments: [Segment]
    var height: CGFloat = 12
    var showsLegend = true

    private var visible: [Segment] { segments.filter { $0.value > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let total = max(visible.reduce(0.0) { $0 + Double($1.value) }, 1)
                let gap: CGFloat = 2
                let usable = max(geometry.size.width - gap * CGFloat(max(visible.count - 1, 0)), 0)
                HStack(spacing: gap) {
                    ForEach(visible) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(usable * CGFloat(Double(segment.value) / total), 2))
                    }
                }
            }
            .frame(height: height)
            .background(Color.primary.opacity(0.08))
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel(visible.map { $0.label }.joined(separator: ", "))

            if showsLegend {
                HStack(spacing: 18) {
                    ForEach(visible) { segment in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(segment.color)
                                .frame(width: 8, height: 8)
                            Text(segment.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

/// The rounded, bordered table container used on every screen.
struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}

/// Small grey column titles above a table.
struct ColumnHeader: View {
    /// Title, width (nil = flexible) and alignment for each column, left to right.
    let columns: [(title: String, width: CGFloat?, alignment: Alignment)]
    /// Space taken by the checkbox column.
    var leading: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: leading - 12)
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                if let width = column.width {
                    Text(column.title).frame(width: width, alignment: column.alignment)
                } else {
                    Text(column.title).frame(maxWidth: .infinity, alignment: column.alignment)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension Theme {
    static let usedSpace = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let videos = Color(red: 0.12, green: 0.25, blue: 0.56)
    static let images = Theme.accent
    static let installers = Color(red: 0.88, green: 0.54, blue: 0.18)
    static let backups = Color(red: 0.54, green: 0.26, blue: 0.0)
    static let archives = Color(red: 0.60, green: 0.63, blue: 0.68)
    static let reviewBar = Color(red: 0.88, green: 0.54, blue: 0.18)
}
