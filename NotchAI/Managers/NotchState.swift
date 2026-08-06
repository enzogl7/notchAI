import Foundation
import Combine

@MainActor
final class NotchState: ObservableObject {

    @Published var isExpanded = false

    @Published var isPinned = false

    @Published var topInset: CGFloat = 0

    @Published var notchWidth: CGFloat = 0

    @Published var contentHeight: CGFloat = 0
}
