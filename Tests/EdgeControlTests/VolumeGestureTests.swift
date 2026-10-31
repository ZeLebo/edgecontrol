import Testing
@testable import EdgeControl

struct VolumeGestureTests {
    @Test func absoluteLevelsAndCancellation() {
        var gesture = VolumeGesture()
        var time = 0.0
        func frame(_ x: Double?, y: Double = 0.02) -> TrackpadFrame {
            time += 0.01
            return TrackpadFrame(timestamp: time, contacts: x.map { [TrackpadContact(id: 1, x: $0, y: y)] } ?? [])
        }
        #expect(gesture.process(frame(0.1)) == .inactive)
        #expect(gesture.process(frame(nil)) == .inactive)
        #expect(gesture.process(frame(0.1)) == .inactive)
        #expect(gesture.process(frame(0.5)).percent == 50)
        #expect(gesture.process(frame(0)).percent == 0)
        #expect(gesture.process(frame(1)).percent == 100)
        #expect(gesture.process(frame(0.8, y: 0.2)) == .inactive)
        #expect(gesture.process(frame(0.2)) == .inactive)
        #expect(gesture.process(frame(nil)) == .inactive)
        #expect(gesture.process(frame(0.1)) == .inactive)
        #expect(gesture.process(frame(0.1)) == .inactive)
        #expect(gesture.process(frame(0.12)).isActive)
        #expect(gesture.reset() == .inactive)
        #expect(gesture.process(frame(0.8)) == .inactive)
    }
    @Test func entryFromOutsideAndInvalidDataNeverActivate() {
        var gesture = VolumeGesture()
        _ = gesture.process(.init(timestamp: 1, contacts: []))
        _ = gesture.process(.init(timestamp: 2, contacts: [.init(id: 1, x: 0.2, y: 0.3)]))
        #expect(gesture.process(.init(timestamp: 3, contacts: [.init(id: 1, x: 0.8, y: 0.02)])) == .inactive)
        _ = gesture.process(.init(timestamp: 4, contacts: []))
        _ = gesture.process(.init(timestamp: 5, contacts: [.init(id: 1, x: 0.2, y: 0.02)]))
        #expect(gesture.process(.init(timestamp: 6, contacts: [.init(id: 1, x: .nan, y: 0.02)])) == .inactive)
    }
}
