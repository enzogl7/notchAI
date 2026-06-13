import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let agentMonitor = AgentMonitor()
    private let notchState = NotchState()
    private var notchController: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        agentMonitor.startMonitoring()
        notchController = NotchWindowController(
            agentMonitor: agentMonitor,
            notchState: notchState
        )
    }
}
