import Testing
@testable import EdgeControl

struct MediaControllerTests {
    @Test func distinguishesTracksFromTenSecondSeek() throws {
        #expect(MediaRequest(action: .nextTrack).command == 4)
        #expect(MediaRequest(action: .previousTrack).command == 5)
        let forward = MediaRequest(action: .seekForward)
        #expect(forward.command == 17)
        #expect(forward.interval == 10)
        let backward = MediaRequest(action: .seekBackward)
        #expect(backward.command == 18)
        #expect(backward.interval == 10)
    }

    @Test func deliberateMovementSendsOnlyOneCommandPerGesture() throws {
        var gesture = MediaMotion()
        #expect(try gesture.consume(.relative(5), action: .tracks) == nil)
        #expect(try gesture.consume(.relative(7), action: .tracks) == .nextTrack)
        #expect(try gesture.consume(.relative(80), action: .tracks) == nil)
        gesture.reset()
        #expect(try gesture.consume(.relative(-12), action: .seek) == .seekBackward)
        #expect(throws: MediaControlError.self) { try gesture.consume(.absolute(90), action: .tracks) }
        #expect(throws: MediaControlError.self) { try gesture.consume(.relative(.nan), action: .seek) }
    }
}
