import SwiftUI

struct NotchView: View {

    @EnvironmentObject private var agentMonitor: AgentMonitor
    @EnvironmentObject private var permissionCenter: PermissionCenter
    @EnvironmentObject private var notchState: NotchState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black

                expanded
                    .frame(width: geo.size.width)
                    .padding(.top, notchState.topInset)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        notchState.contentHeight = $0
                    }
            }
            .frame(
                width: notchState.isExpanded ? geo.size.width : notchState.notchWidth,
                height: notchState.isExpanded ? geo.size.height : notchState.topInset,
                alignment: .top
            )
            .clipShape(BottomRoundedRectangle(radius: 18))
            .shadow(
                color: .black.opacity(notchState.isExpanded ? 0.4 : 0),
                radius: 12,
                y: 6
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain")
                Text("NotchAI")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if permissionCenter.pending.count > 1 {
                    Text("\(permissionCenter.pending.count) pedidos")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                } else if permissionCenter.pending.isEmpty {
                    Text("\(agentMonitor.activeCount) ativos")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Divider().overlay(.white.opacity(0.12))

            if !permissionCenter.pending.isEmpty {
                permissionsSection
            } else if agentMonitor.sessions.isEmpty {
                agentsSection
            } else {
                sessionsSection
                Divider().overlay(.white.opacity(0.12))
                agentsSection
            }

            if permissionCenter.pending.isEmpty, let quota = agentMonitor.quota {
                Divider().overlay(.white.opacity(0.12))
                quotaSection(quota)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var permissionsSection: some View {
        VStack(spacing: 8) {
            ForEach(permissionCenter.pending) { request in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: request.kind.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text("\(request.agentName) · \(request.projectName)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(request.toolName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Text(request.summary)
                        .font(.system(size: 11, design: request.kind.textDesign))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(request.kind.textLineLimit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    options(for: request)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                )
            }
        }
    }

    @ViewBuilder
    private func options(for request: AgentRequest) -> some View {
        if request.options.allSatisfy({ $0.description == nil }) {
            HStack(spacing: 8) {
                Spacer()
                ForEach(request.options) { option in
                    Button(option.label) { permissionCenter.choose(option, for: request) }
                        .buttonStyle(PermissionButtonStyle(tint: option.tint))
                }
            }
        } else {
            VStack(spacing: 6) {
                ForEach(request.options) { option in
                    Button { permissionCenter.choose(option, for: request) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.system(size: 12, weight: .medium))
                            if let description = option.description {
                                Text(description)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(ChoiceRowStyle())
                }
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(agentMonitor.sessions) { session in
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.state.color)
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.projectName)
                            .font(.system(size: 12, weight: .medium))
                        if let branch = session.gitBranch {
                            Text(branch)
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Spacer()

                    Text(session.state.label)
                        .font(.system(size: 10))
                        .foregroundStyle(session.state.color.opacity(0.9))
                }
            }
        }
    }

    private func quotaSection(_ quota: UsageQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fiveHour = quota.fiveHour { quotaRow("5h", fiveHour) }
            if let sevenDay = quota.sevenDay { quotaRow("7d", sevenDay) }

            Text("lido às \(quota.readAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private func quotaRow(_ title: String, _ window: UsageQuota.Window) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18, alignment: .leading)

            ProgressView(value: min(max(window.usedPercentage, 0), 100), total: 100)
                .tint(window.tint)

            Text("\(Int(window.usedPercentage.rounded()))%")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .frame(width: 34, alignment: .trailing)

            Text(window.resetsAt, style: .relative)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private var agentsSection: some View {
        HStack(spacing: 18) {
            ForEach(agentMonitor.agents) { agent in
                HStack(spacing: 6) {
                    Image(systemName: agent.icon)
                        .font(.system(size: 11))
                    Text(agent.name)
                        .font(.system(size: 11))
                    Circle()
                        .fill(agent.isRunning ? Color.green : Color.white.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                .opacity(agent.isRunning ? 1 : 0.45)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct Hoverable<Content: View>: View {

    let isPressed: Bool
    let tint: Color
    let base: Double
    let hover: Double
    let pressed: Double
    @ViewBuilder let content: (Color) -> Content

    @State private var isHovering = false

    var body: some View {
        content(tint.opacity(isPressed ? pressed : isHovering ? hover : base))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

private struct PermissionButtonStyle: ButtonStyle {

    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Hoverable(isPressed: configuration.isPressed, tint: tint, base: 0.18, hover: 0.3, pressed: 0.4) { fill in
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
    }
}

private struct ChoiceRowStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        Hoverable(isPressed: configuration.isPressed, tint: .white, base: 0.1, hover: 0.18, pressed: 0.24) { fill in
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(fill))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private extension AgentRequest.Kind {

    var icon: String {
        switch self {
        case .permission: "hand.raised.fill"
        case .question: "questionmark.circle.fill"
        }
    }

    var textDesign: Font.Design {
        switch self {
        case .permission: .monospaced
        case .question: .default
        }
    }

    var textLineLimit: Int {
        switch self {
        case .permission: 2
        case .question: 3
        }
    }
}

private extension AgentRequest.Option {

    var tint: Color {
        switch id {
        case "allow": .green
        case "deny": .red
        default: .white
        }
    }
}

private extension UsageQuota.Window {

    var tint: Color {
        switch usedPercentage {
        case ..<70: .green
        case ..<90: .orange
        default: .red
        }
    }
}

private extension SessionState {

    var color: Color {
        switch self {
        case .working: .green
        case .waitingForInput: .orange
        case .waitingForPermission: .red
        case .idle: .white.opacity(0.3)
        }
    }

    var label: String {
        switch self {
        case .working: "trabalhando"
        case .waitingForInput: "aguardando"
        case .waitingForPermission: "permissão"
        case .idle: "ocioso"
        }
    }
}

private struct BottomRoundedRectangle: Shape {

    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
