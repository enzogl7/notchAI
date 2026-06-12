import Foundation

struct Agent: Identifiable {
    let id = UUID()
    let name: String
    var isRunning: Bool
}
