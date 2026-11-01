import AppKit
import Testing
@testable import EdgeControl

@MainActor
struct ApplicationExclusionsTests {
    @Test func startsWithTheActualFrontmostApplicationAndDoesNotStartTwice() {
        let center = NotificationCenter()
        let state = State("example.editor")
        let monitor = ApplicationExclusions(notificationCenter: center, frontmostBundleID: { state.bundleID })
        var received: [String?] = []
        monitor.onChange = { received.append($0) }
        #expect(received.isEmpty)
        monitor.start()
        monitor.start()
        #expect(received == ["example.editor"])
        #expect(monitor.currentBundleID == "example.editor")
        monitor.stop()
    }

    @Test func activationReadsCurrentStateRatherThanAStaleNotificationPayload() {
        let center = NotificationCenter()
        let state = State("example.editor")
        let monitor = ApplicationExclusions(notificationCenter: center, frontmostBundleID: { state.bundleID })
        var received: [String?] = []
        monitor.onChange = { received.append($0) }
        monitor.start()
        state.bundleID = "example.game"
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                    userInfo: [NSWorkspace.applicationUserInfoKey: "stale payload"])
        #expect(received == ["example.editor", "example.game"])
        #expect(monitor.currentBundleID == "example.game")
        monitor.stop()
    }

    @Test func duplicateActivationsDoNotRestartInputAndMissingIdentityIsDelivered() {
        let center = NotificationCenter()
        let state = State("example.game")
        let monitor = ApplicationExclusions(notificationCenter: center, frontmostBundleID: { state.bundleID })
        var received: [String?] = []
        monitor.onChange = { received.append($0) }
        monitor.start()
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        state.bundleID = nil
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(received == ["example.game", nil])
        monitor.stop()
    }

    @Test func stopIgnoresFurtherActivationsAndRestartPublishesTheLatestApp() {
        let center = NotificationCenter()
        let state = State("example.game")
        let monitor = ApplicationExclusions(notificationCenter: center, frontmostBundleID: { state.bundleID })
        var received: [String?] = []
        monitor.onChange = { received.append($0) }
        monitor.start()
        monitor.stop()
        state.bundleID = "example.editor"
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
        #expect(received == ["example.game"])
        #expect(monitor.currentBundleID == nil)
        monitor.start()
        #expect(received == ["example.game", "example.editor"])
        monitor.stop()
    }

    private final class State {
        var bundleID: String?
        init(_ bundleID: String?) { self.bundleID = bundleID }
    }
}
