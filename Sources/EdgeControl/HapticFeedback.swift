import AppKit

@MainActor
final class HapticFeedback {
    private var gate = HapticFeedbackGate()

    func levelChanged(to percent: Int, enabled: Bool) {
        if gate.acceptLevel(percent, enabled: enabled, at: ProcessInfo.processInfo.systemUptime) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func actionPerformed(enabled: Bool) {
        if gate.acceptAction(enabled: enabled, at: ProcessInfo.processInfo.systemUptime) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func reset() { gate = HapticFeedbackGate() }
}

struct HapticFeedbackGate {
    private var lastLevel: Int?
    private var lastFeedbackAt: Double?

    mutating func acceptLevel(_ percent: Int, enabled: Bool, at time: Double) -> Bool {
        guard (0...100).contains(percent), time.isFinite, time >= 0 else { return false }
        let changed = lastLevel != percent
        lastLevel = percent
        return changed && acceptAction(enabled: enabled, at: time)
    }

    mutating func acceptAction(enabled: Bool, at time: Double) -> Bool {
        guard enabled, time.isFinite, time >= 0,
              lastFeedbackAt.map({ time - $0 >= 0.05 }) ?? true else { return false }
        lastFeedbackAt = time
        return true
    }
}
