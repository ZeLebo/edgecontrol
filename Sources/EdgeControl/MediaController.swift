import CoreFoundation
import Darwin
import Foundation

enum MediaAction: String, Equatable {
    case previousTrack, nextTrack, seekBackward, seekForward
    var title: String {
        switch self {
        case .previousTrack: "Previous Track"
        case .nextTrack: "Next Track"
        case .seekBackward: "Seek Backward 10 Seconds"
        case .seekForward: "Seek Forward 10 Seconds"
        }
    }
    var symbol: String {
        switch self {
        case .previousTrack: "backward.end.fill"
        case .nextTrack: "forward.end.fill"
        case .seekBackward: "gobackward.10"
        case .seekForward: "goforward.10"
        }
    }
}

struct MediaRequest: Equatable {
    let command: UInt32
    let interval: Double?

    init(action: MediaAction) {
        switch action {
        case .nextTrack: command = 4; interval = nil
        case .previousTrack: command = 5; interval = nil
        case .seekForward: command = 17; interval = 10
        case .seekBackward: command = 18; interval = 10
        }
    }
}

struct MediaMotion {
    private var distance = 0.0
    private var fired = false

    mutating func consume(_ change: LevelChange, action: EdgeAction) throws -> MediaAction? {
        guard case let .relative(delta) = change, delta.isFinite,
              action == .tracks || action == .seek else {
            throw MediaControlError("Media gestures require finite relative movement")
        }
        guard !fired else { return nil }
        distance += delta
        guard abs(distance) >= 12 else { return nil }
        fired = true
        if action == .tracks { return distance > 0 ? .nextTrack : .previousTrack }
        return distance > 0 ? .seekForward : .seekBackward
    }

    mutating func reset() { distance = 0; fired = false }
}

@MainActor
final class MediaController {
    private var api: MediaRemoteAPI?

    func perform(_ action: MediaAction) throws {
        let request = MediaRequest(action: action)
        let api = try self.api ?? MediaRemoteAPI()
        self.api = api
        let options: CFDictionary?
        if let interval = request.interval {
            options = [api.skipIntervalKey as String: NSNumber(value: interval)] as CFDictionary
        } else {
            options = nil
        }
        guard api.send(request.command, options) != 0 else {
            throw MediaControlError("The current player did not accept the media command")
        }
    }
}

struct MediaControlError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// Command values: WebKit's MediaRemoteSPI.h. Send ABI: theos/headers MediaRemote.h.
// Only sends commands; no now-playing reads or entitled host processes are used.
private final class MediaRemoteAPI {
    typealias Send = @convention(c) (UInt32, CFDictionary?) -> UInt8
    private let library: UnsafeMutableRawPointer
    let send: Send
    let skipIntervalKey: CFString

    init() throws {
        let path = try systemPrivateFrameworkPath("MediaRemote")
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw MediaControlError("MediaRemote is unavailable")
        }
        self.library = library
        guard let function = dlsym(library, "MRMediaRemoteSendCommand"),
              let constant = dlsym(library, "kMRMediaRemoteOptionSkipInterval"),
              let key = constant.assumingMemoryBound(to: Unmanaged<CFString>?.self).pointee?.takeUnretainedValue() else {
            dlclose(library)
            throw MediaControlError("Required MediaRemote symbols are unavailable")
        }
        send = unsafeBitCast(function, to: Send.self)
        skipIntervalKey = key
    }

    deinit { dlclose(library) }
}
