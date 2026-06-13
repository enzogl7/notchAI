import AppKit
import SwiftUI
import Combine

@MainActor
final class NotchWindowController {

    private let panel: NSPanel
    private let agentMonitor: AgentMonitor
    private let notchState: NotchState
    private var cancellables = Set<AnyCancellable>()
    private var hoverTimer: Timer?

    private func collapsedSize(topInset: CGFloat, notchWidth: CGFloat) -> CGSize {
        CGSize(width: max(notchWidth, 180), height: topInset + 28)
    }

    private func expandedSize(topInset: CGFloat, notchWidth: CGFloat) -> CGSize {
        let agentsHeight = CGFloat(agentMonitor.agents.count) * 28
        let sessionsHeight = agentMonitor.sessions.isEmpty
            ? 0
            : CGFloat(agentMonitor.sessions.count) * 36 + 24
        return CGSize(
            width: max(notchWidth, 320),
            height: topInset + 64 + agentsHeight + sessionsHeight
        )
    }

    init(agentMonitor: AgentMonitor, notchState: NotchState) {
        self.agentMonitor = agentMonitor
        self.notchState = notchState

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 28),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        installHostingView()
        observe()

        syncTopInset()
        reposition()
        panel.orderFrontRegardless()
        startHoverTracking()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
    }

    private func installHostingView() {
        let root = NotchView()
            .environmentObject(agentMonitor)
            .environmentObject(notchState)

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []

        let container = NSView()
        panel.contentView = container

        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    private func observe() {
        notchState.$isExpanded
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &cancellables)

        agentMonitor.$sessions
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.notchState.isExpanded else { return }
                self.reposition()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncTopInset()
                self?.reposition()
            }
            .store(in: &cancellables)
    }

    private func startHoverTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHover()
            }
        }
    }

    private func updateHover() {
        let inside = panel.frame.contains(NSEvent.mouseLocation)
        guard notchState.isExpanded != inside else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            notchState.isExpanded = inside
        }
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: \.hasNotch) ?? .main
    }

    private func syncTopInset() {
        notchState.topInset = targetScreen?.notchTopInset ?? 0
    }

    private func reposition() {
        guard let screen = targetScreen else { return }

        let topInset = screen.notchTopInset
        let notchWidth = screen.notchWidth

        let size = notchState.isExpanded
            ? expandedSize(topInset: topInset, notchWidth: notchWidth)
            : collapsedSize(topInset: topInset, notchWidth: notchWidth)

        let originX = screen.frame.midX - size.width / 2
        let originY = screen.frame.maxY - size.height

        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)

        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }
}
