import Testing
@testable import EdgeControl

struct LevelAccumulatorTests {
    @Test func absoluteLevelsNeedNoSeedAndRemainExact() throws {
        var levels = LevelAccumulator()
        for percent in [0, 50, 100, 73] {
            #expect(try levels.apply(.absolute(percent)) == percent)
        }
    }

    @Test func relativeLevelsRequireARealStartingLevel() throws {
        var levels = LevelAccumulator()
        #expect(throws: (any Error).self) { try levels.apply(.relative(10)) }
        try levels.start(at: 70)
        #expect(try levels.apply(.relative(10)) == 80)
        levels.reset()
        #expect(throws: (any Error).self) { try levels.apply(.relative(10)) }
        try levels.start(at: 42)
        #expect(try levels.apply(.relative(0)) == 42)
    }

    @Test func fractionalMovementIsPreservedUntilOutputRounding() throws {
        var levels = LevelAccumulator()
        try levels.start(at: 70)
        var output = 70
        for _ in 0..<100 { output = try levels.apply(.relative(0.01)) }
        #expect(output == 71)
        for _ in 0..<100 { output = try levels.apply(.relative(-0.01)) }
        #expect(output == 70)
    }

    @Test func reversalAtEitherLimitHasNoDeadTravel() throws {
        var levels = LevelAccumulator()
        try levels.start(at: 99)
        #expect(try levels.apply(.relative(40)) == 100)
        #expect(try levels.apply(.relative(-1)) == 99)
        #expect(try levels.apply(.relative(-200)) == 0)
        #expect(try levels.apply(.relative(1)) == 1)
    }

    @Test func invalidInputDoesNotReplaceThePreviousLevel() throws {
        var levels = LevelAccumulator()
        try levels.start(at: 70)
        for value in [-1, 101] {
            #expect(throws: (any Error).self) { try levels.start(at: value) }
            #expect(throws: (any Error).self) { try levels.apply(.absolute(value)) }
        }
        for delta in [Double.nan, .infinity, -.infinity] {
            #expect(throws: (any Error).self) { try levels.apply(.relative(delta)) }
        }
        #expect(try levels.apply(.relative(1)) == 71)
    }
}
