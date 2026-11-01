import CoreGraphics
import Testing
@testable import EdgeControl

struct TapClickSuppressionTests {
    @Test func profileTailSurvivesTheNewRecognizersEmptyFrames() {
        var suppression = TapClickSuppression()
        let released = TapUpdate(command: TapCommand(zone: .topRight, action: .nextProfile), suppressClicks: true, suppressionUntil: 1.08)
        #expect(suppression.update(released, at: 1) == true)
        suppression.reset() // Settings change resets recognition synchronously.
        #expect(suppression.preserveProfileTail(until: released.suppressionUntil, at: 1) == true)
        #expect(suppression.update(.inactive, at: 1.01) == true)
        #expect(suppression.update(.inactive, at: 1.07) == true)
        #expect(suppression.advance(to: 1.08) == false)
    }

    @Test func ordinaryCancellationStillClearsTheFirstTapWindowImmediately() {
        var suppression = TapClickSuppression()
        #expect(suppression.update(TapUpdate(command: nil, suppressClicks: true, suppressionUntil: 1.35), at: 1) == true)
        #expect(suppression.update(.inactive, at: 1.01) == false)
    }

    @Test func profileWindowIsBoundedAndClickPairsRemainBalancedAtExpiry() {
        var suppression = TapClickSuppression()
        var clicks = CursorClickFilter()
        clicks.setSuppression(suppression.preserveProfileTail(until: 2, at: 1))
        #expect(clicks.shouldDrop(.leftMouseDown) == true)
        clicks.setSuppression(suppression.advance(to: 1.08))
        #expect(clicks.shouldDrop(.leftMouseUp) == true)
        #expect(clicks.shouldDrop(.leftMouseDown) == false)
        #expect(suppression.preserveProfileTail(until: .infinity, at: 2) == false)
    }
}
