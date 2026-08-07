import SwiftUI

@main
struct NotchAIApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(appDelegate.agentMonitor)
        } label: {
            MenuBarLabel(agentMonitor: appDelegate.agentMonitor)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {

    @ObservedObject var agentMonitor: AgentMonitor

    var body: some View {
        Image(systemName: "brain")
        Text(label)
    }

    private var label: String {
        guard let used = agentMonitor.quota?.fiveHour?.usedPercentage else {
            return "\(agentMonitor.activeCount)"
        }
        return "\(agentMonitor.activeCount) · \(Int(used.rounded()))%"
    }
}
