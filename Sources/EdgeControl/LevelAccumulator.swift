import Foundation

struct LevelAccumulator {
    private var level: Double?

    mutating func start(at percent: Int) throws {
        guard (0...100).contains(percent) else { throw LevelAccumulatorError.invalidLevel }
        level = Double(percent)
    }

    mutating func apply(_ change: LevelChange) throws -> Int {
        let updated: Double
        switch change {
        case .absolute(let percent):
            guard (0...100).contains(percent) else { throw LevelAccumulatorError.invalidLevel }
            updated = Double(percent)
        case .relative(let delta):
            guard delta.isFinite else { throw LevelAccumulatorError.invalidDelta }
            guard let level else { throw LevelAccumulatorError.missingInitialLevel }
            // Clamp the accumulator itself, so reversing at a limit responds immediately.
            updated = min(100, max(0, level + delta))
        }
        level = updated
        return Int(updated.rounded())
    }

    mutating func reset() { level = nil }
}

private enum LevelAccumulatorError: LocalizedError {
    case invalidLevel, invalidDelta, missingInitialLevel
    var errorDescription: String? {
        switch self {
        case .invalidLevel: "Level must be between 0 and 100"
        case .invalidDelta: "Relative movement must be finite"
        case .missingInitialLevel: "Relative adjustment needs the current system level"
        }
    }
}
