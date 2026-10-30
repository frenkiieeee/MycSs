import SwiftUI

/// A layout that flows its subviews into rows, like text.
///
/// The karaoke view draws a line as a row of individual words so that each word
/// can be filled in as it is sung. A plain `HStack` cannot do that: it never
/// wraps, so a long line either overflows the screen or is truncated. This layout
/// breaks the words into rows when they run out of width.
struct WrappingHStack: Layout {

    /// The gap between words on the same row.
    var spacing: CGFloat = 0
    /// The gap between rows.
    var lineSpacing: CGFloat = 10
    /// The alignment of each row within the available width.
    var rowAlignment: HorizontalAlignment = .leading

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)

        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: min(width, maxWidth == .infinity ? width : maxWidth), height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x: CGFloat
            switch rowAlignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    // MARK: - Arranging

    private struct Item {
        var index: Int
        var size: CGSize
    }

    private struct Row {
        var items: [Item] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Breaks the subviews into rows that fit the available width.
    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            // The size the view reports for itself. A word that carries its
            // trailing space in the text measures wider than the word, which is
            // what makes the spacing come out wrong, so the trailing space is
            // measured separately and the gap is added by the layout.
            let reported = subviews[index].sizeThatFits(.unspecified)
            let size = CGSize(width: reported.width, height: reported.height)

            let needed = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if !current.items.isEmpty, needed > maxWidth, maxWidth.isFinite {
                rows.append(current)
                current = Row()
            }

            current.width = current.items.isEmpty
                ? size.width
                : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.items.append(Item(index: index, size: size))
        }

        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
