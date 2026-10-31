import CoreGraphics
import Testing
@testable import EdgeControl

struct CursorClickFilterTests {
    @Test func normalClickPairsAndOtherButtonsPassThrough() {
        var filter = CursorClickFilter()
        #expect(filter.shouldDrop(.leftMouseDown) == false)
        #expect(filter.shouldDrop(.leftMouseUp) == false)
        filter.setSuppression(true)
        #expect(filter.shouldDrop(.rightMouseDown) == false)
        #expect(filter.shouldDrop(.rightMouseUp) == false)
        #expect(filter.shouldDrop(.mouseMoved) == false)
    }

    @Test func aBlockedDownKeepsItsMatchingUpBlockedAfterTheZoneEnds() {
        var filter = CursorClickFilter()
        filter.setSuppression(true)
        #expect(filter.shouldDrop(.leftMouseDown) == true)
        filter.setSuppression(false)
        #expect(filter.shouldDrop(.leftMouseUp) == true)
        #expect(filter.shouldDrop(.leftMouseDown) == false)
        #expect(filter.shouldDrop(.leftMouseUp) == false)
    }

    @Test func enteringAZoneDoesNotConsumeTheUpOfAnUnblockedClick() {
        var filter = CursorClickFilter()
        #expect(filter.shouldDrop(.leftMouseDown) == false)
        filter.setSuppression(true)
        #expect(filter.shouldDrop(.leftMouseUp) == false)
        #expect(filter.shouldDrop(.leftMouseDown) == true)
        #expect(filter.shouldDrop(.leftMouseUp) == true)
        filter.reset()
        #expect(filter.shouldDrop(.leftMouseDown) == false)
        #expect(filter.shouldDrop(.leftMouseUp) == false)
    }
}
