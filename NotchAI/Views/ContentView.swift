import SwiftUI

struct ContentView: View {

    @StateObject private var agentMonitor = AgentMonitor()

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            Text("NotchAI")
                .font(.title)

            ForEach(agentMonitor.agents) { agent in
                HStack {
                    Text(agent.name)

                    Spacer()

                    Text(agent.isRunning ? "🟢 Online" : "🔴 Offline")
                }
            }
        }
        .padding()
        .frame(width: 320, height: 220)
        .onAppear {
            agentMonitor.startMonitoring()
        }
    }
}
