import Foundation
import Testing
@testable import EdgeControl

struct TrackpadInputTests {
    @Test func findsBuiltInTrackpadWhenOpaqueFlagIsFalse() throws {
        // Regression: an internal trackpad may report an opaque=false surface.
        #expect(try builtInTrackpadIndex(in: [(isBuiltIn: true, isOpaqueSurface: false)]) == 0)
        #expect(try builtInTrackpadIndex(in: [
            (isBuiltIn: false, isOpaqueSurface: true),
            (isBuiltIn: true, isOpaqueSurface: false),
        ]) == 1)
    }

    @Test func rejectsMissingOrAmbiguousBuiltInTrackpad() {
        #expect(throws: TrackpadInputError.self) { try builtInTrackpadIndex(in: []) }
        #expect(throws: TrackpadInputError.self) {
            try builtInTrackpadIndex(in: [(isBuiltIn: false, isOpaqueSurface: true)])
        }
        #expect(throws: TrackpadInputError.self) {
            try builtInTrackpadIndex(in: [
                (isBuiltIn: true, isOpaqueSurface: true),
                (isBuiltIn: true, isOpaqueSurface: false),
            ])
        }
    }

    @Test func copiesPhysicalContactsIncludingStationaryFingers() throws {
        let bytes = contact(id: 11, state: 3, x: 0.25, y: 0.02)
            + contact(id: 12, state: 4, x: 0.75, y: 0.03)
        let frame = try decode(bytes, count: 2).get()
        #expect(frame.timestamp == 100)
        #expect(frame.contacts.map(\.id) == [11, 12])
        #expect(abs(frame.contacts[0].x - 0.25) < 0.000001)
        #expect(abs(frame.contacts[1].y - 0.03) < 0.000001)
    }

    @Test func hoverAndReleaseAreNotHeldContacts() throws {
        let bytes = contact(id: 11, state: 2) + contact(id: 12, state: 5)
        #expect(try decode(bytes, count: 2).get().contacts.isEmpty)
        #expect(try decodeTrackpadContacts(nil, count: 0, timestamp: 100).get().contacts.isEmpty)
    }

    @Test func malformedFramesAreRejected() {
        #expect(isFailure(decodeTrackpadContacts(nil, count: 1, timestamp: 100)))
        #expect(isFailure(decodeTrackpadContacts(nil, count: -1, timestamp: 100)))
        #expect(isFailure(decodeTrackpadContacts(nil, count: 33, timestamp: 100)))
        #expect(isFailure(decode(contact(state: 42), count: 1)))
        for value: Float in [-0.01, 1.01, .nan, .infinity] {
            #expect(isFailure(decode(contact(x: value), count: 1)))
            #expect(isFailure(decode(contact(y: value), count: 1)))
        }
        #expect(isFailure(decode(contact(id: 5) + contact(id: 5), count: 2)))
    }

    private func contact(id: Int32 = 1, state: Int32 = 4, x: Float = 0.5, y: Float = 0.02) -> [UInt8] {
        // Fixed byte offsets from the published private ABI, independent of Swift struct layout.
        var bytes = [UInt8](repeating: 0, count: 96)
        bytes.withUnsafeMutableBytes { raw in
            raw.storeBytes(of: id, toByteOffset: 16, as: Int32.self)
            raw.storeBytes(of: state, toByteOffset: 20, as: Int32.self)
            raw.storeBytes(of: x, toByteOffset: 32, as: Float.self)
            raw.storeBytes(of: y, toByteOffset: 36, as: Float.self)
        }
        return bytes
    }

    private func decode(_ bytes: [UInt8], count: Int32) -> Result<TrackpadFrame, TrackpadInputError> {
        bytes.withUnsafeBytes { decodeTrackpadContacts($0.baseAddress, count: count, timestamp: 100) }
    }

    private func isFailure(_ result: Result<TrackpadFrame, TrackpadInputError>) -> Bool {
        if case .failure = result { return true }
        return false
    }
}
