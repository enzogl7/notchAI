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

    var notchRect: NSRect {
        let width = notchWidth
        let height = notchTopInset
        return NSRect(
            x: frame.midX - width / 2,
            y: frame.maxY - height,
            width: width,
            height: height
        )
    }

    // ponytail: sem API pública pra fullscreen de terceiros; em fullscreen a barra
    // de menus deixa de ser reservada e visibleFrame encosta no topo do frame.
    var isFullScreenActive: Bool {
        visibleFrame.maxY >= frame.maxY - 1
    }
}
