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
    private var hoverTicks = 0

    private let tickInterval: TimeInterval = 0.1
    private let ticksToOpen = 3
    private let ticksToClose = 2
    private let hoverSlack: CGFloat = 6

    private func expandedSize(topInset: CGFloat, notchWidth: CGFloat) -> CGSize {
        let sessionsHeight = agentMonitor.sessions.isEmpty
            ? 0
            : CGFloat(agentMonitor.sessions.count) * 36 + 24
        return CGSize(
            width: max(notchWidth, 480),
            height: topInset + 92 + sessionsHeight
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

        syncScreenMetrics()
        reposition()
        startHoverTracking()
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
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
            .sink { [weak self] isExpanded in
                self?.panel.ignoresMouseEvents = !isExpanded
            }
            .store(in: &cancellables)

        agentMonitor.$sessions
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reposition()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncScreenMetrics()
                self?.reposition()
            }
            .store(in: &cancellables)
    }

    private func startHoverTracking() {
        hoverTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateHover()
            }
        }
    }

    private func updateHover() {
        guard let screen = targetScreen, screen.hasNotch else { return }

        let target = notchState.isExpanded ? panel.frame : hoverRect(on: screen)
        let inside = target.contains(NSEvent.mouseLocation)
        let desired = inside && !(!notchState.isExpanded && screen.isFullScreenActive)

        guard desired != notchState.isExpanded else {
            hoverTicks = 0
            return
        }

        hoverTicks += 1
        guard hoverTicks >= (desired ? ticksToOpen : ticksToClose) else { return }
        hoverTicks = 0

        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            notchState.isExpanded = desired
        }
    }

    private func hoverRect(on screen: NSScreen) -> NSRect {
        let rect = screen.notchRect
        return NSRect(
            x: rect.minX,
            y: rect.minY - hoverSlack,
            width: rect.width,
            height: rect.height + hoverSlack
        )
    }

    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: \.hasNotch)
    }

    private func syncScreenMetrics() {
        notchState.topInset = targetScreen?.notchTopInset ?? 0
        notchState.notchWidth = targetScreen?.notchWidth ?? 0
    }

    private func reposition() {
        guard let screen = targetScreen else {
            notchState.isExpanded = false
            panel.orderOut(nil)
            return
        }

        let topInset = screen.notchTopInset
        let notchWidth = screen.notchWidth

        let size = expandedSize(topInset: topInset, notchWidth: notchWidth)

        let originX = screen.frame.midX - size.width / 2
        let originY = screen.frame.maxY - size.height

        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)

        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }
}
