import AppKit

@MainActor
final class ApplicationExclusions {
    var onChange: ((String?) -> Void)?
    private(set) var currentBundleID: String?
    private let notificationCenter: NotificationCenter
    private let frontmostBundleID: @MainActor () -> String?
    private var observation: NSObjectProtocol?

    init(notificationCenter: NotificationCenter? = nil,
         frontmostBundleID: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) {
        self.notificationCenter = notificationCenter ?? NSWorkspace.shared.notificationCenter
        self.frontmostBundleID = frontmostBundleID
    }

    func start() {
        guard observation == nil else { return }
        observation = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh(force: true)
    }

    func stop() {
        if let observation { notificationCenter.removeObserver(observation) }
        observation = nil
        currentBundleID = nil
    }

    private func refresh(force: Bool = false) {
        // Query the actual foreground app: a queued activation payload may already be stale.
        guard observation != nil else { return }
        let bundleID = frontmostBundleID()
        guard force || bundleID != currentBundleID else { return }
        currentBundleID = bundleID
        onChange?(bundleID)
    }

    isolated deinit { stop() }
}
