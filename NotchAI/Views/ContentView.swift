import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var agentMonitor: AgentMonitor

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            Text("NotchAI")
                .font(.headline)

            ForEach(agentMonitor.agents) { agent in
                HStack {
                    Image(systemName: agent.icon)
                        .frame(width: 20)

                    Text(agent.name)

                    Spacer()

                    Text(agent.isRunning ? "🟢 Online" : "🔴 Offline")
                }
            }

            Divider()

            Button("Quit NotchAI") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260)
    }
}
