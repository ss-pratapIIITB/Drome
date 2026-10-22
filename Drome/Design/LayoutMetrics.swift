import SwiftUI

enum DromeLayout {
    static let screenMargin: CGFloat = 16
    static let compactMargin: CGFloat = 12
    static let wideMargin: CGFloat = 24
    static let toolbarHeight: CGFloat = 50
    static let bottomToolbarReserve: CGFloat = toolbarHeight + 8
    static let addressBarMinHeight: CGFloat = 44
    static let controlCorner: CGFloat = 12
    static let cardCorner: CGFloat = 16
    static let searchMaxWidth: CGFloat = 560

    static func margin(for width: CGFloat) -> CGFloat {
        if width < 390 { return compactMargin }
        if width > 520 { return wideMargin }
        return screenMargin
    }

    static func contentWidth(_ width: CGFloat, maximum: CGFloat = searchMaxWidth) -> CGFloat {
        max(0, min(width - 2 * margin(for: width), maximum))
    }
}
