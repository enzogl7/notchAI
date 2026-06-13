import Foundation
import Combine

@MainActor
final class NotchState: ObservableObject {

    @Published var isExpanded = false

    @Published var topInset: CGFloat = 0
}
