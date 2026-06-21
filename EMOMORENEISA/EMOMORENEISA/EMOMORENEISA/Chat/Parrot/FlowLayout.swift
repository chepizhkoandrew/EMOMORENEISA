import SwiftUI

struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width && rowWidth > 0 {
                height += rowHeight + vSpacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: max(height, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0
        var rowItems: [(subview: LayoutSubview, size: CGSize)] = []

        func placeRow() {
            var rowX = bounds.minX
            for (sub, size) in rowItems {
                sub.place(at: CGPoint(x: rowX, y: cursorY), proposal: ProposedViewSize(size))
                rowX += size.width + hSpacing
            }
            cursorY += rowHeight + vSpacing
            cursorX = bounds.minX
            rowHeight = 0
            rowItems = []
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > bounds.maxX && !rowItems.isEmpty {
                placeRow()
            }
            rowItems.append((subview, size))
            rowHeight = max(rowHeight, size.height)
            cursorX += size.width + hSpacing
        }
        placeRow()
    }
}
