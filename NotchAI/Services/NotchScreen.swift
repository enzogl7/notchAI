import AppKit

extension NSScreen {

    var hasNotch: Bool {
        safeAreaInsets.top > 0
    }

    var notchHeight: CGFloat {
        safeAreaInsets.top
    }

    var notchWidth: CGFloat {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else { return 0 }
        return frame.width - left.width - right.width
    }

    var menuBarHeight: CGFloat {
        frame.maxY - visibleFrame.maxY
    }

    var notchTopInset: CGFloat {
        hasNotch ? notchHeight : menuBarHeight
    }
}
