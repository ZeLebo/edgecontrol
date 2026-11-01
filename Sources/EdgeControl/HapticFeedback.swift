import Darwin
import Foundation

@MainActor
protocol HapticTransport: AnyObject {
    func start(deviceID: UInt64) throws
    func actuate(_ waveform: HapticWaveform) throws
    func stop() throws
}

enum HapticWaveform: Int32 {
    case weak = 3
    case medium = 4
    case strong = 6
}

@MainActor
final class HapticFeedback {
    private let transport: any HapticTransport
    private let now: @MainActor () -> Double
    private var gate = HapticFeedbackGate()
    private(set) var isReady = false

    init(transport: (any HapticTransport)? = nil,
         now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport ?? MultitouchHapticTransport()
        self.now = now
    }

    func start(deviceID: UInt64) throws {
        isReady = false
        reset()
        try transport.start(deviceID: deviceID)
        isReady = true
    }

    func stop() throws {
        isReady = false
        reset()
        try transport.stop()
    }

    func levelChanged(to percent: Int, enabled: Bool) throws {
        var next = gate
        guard next.acceptLevel(percent, enabled: enabled, at: now()) else {
            gate = next
            return
        }
        let waveform: HapticWaveform = percent <= 33 ? .weak : (percent <= 66 ? .medium : .strong)
        try send(waveform)
        gate = next
    }

    func actionPerformed(enabled: Bool) throws {
        var next = gate
        guard next.acceptAction(enabled: enabled, at: now()) else { return }
        try send(.medium)
        gate = next
    }

    func reset() { gate = HapticFeedbackGate() }

    private func send(_ waveform: HapticWaveform) throws {
        guard isReady else { throw HapticFeedbackError.notStarted }
        try transport.actuate(waveform)
    }
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
              lastFeedbackAt.map({ time - $0 >= 0.051 }) ?? true else { return false }
        lastFeedbackAt = time
        return true
    }
}

enum HapticFeedbackError: LocalizedError {
    case unavailable(String)
    case notStarted
    case operation(String, Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .notStarted: "The trackpad haptic actuator is not ready"
        case let .operation(name, status):
            "\(name) failed (\(String(format: "0x%08x", UInt32(bitPattern: status))))"
        }
    }
}

@MainActor
private final class MultitouchHapticTransport: HapticTransport {
    private var api: MultitouchHapticAPI?
    private var actuator: CFTypeRef?

    func start(deviceID: UInt64) throws {
        try stop()
        let api = try self.api ?? MultitouchHapticAPI()
        self.api = api
        // The ID belongs to the same built-in sensor selected by TrackpadInput.
        guard let created = api.create(deviceID)?.takeRetainedValue() else {
            throw HapticFeedbackError.unavailable("The built-in trackpad does not provide a haptic actuator")
        }
        let status = api.open(created)
        guard status == 0 else { throw HapticFeedbackError.operation("MTActuatorOpen", status) }
        actuator = created
    }

    func actuate(_ waveform: HapticWaveform) throws {
        guard let actuator, let api else { throw HapticFeedbackError.notStarted }
        // niw's single-pulse example uses UInt32 + two Float32 zeros. These are
        // undocumented waveform parameters, not a documented amplitude control.
        let status = api.actuate(actuator, waveform.rawValue, 0, 0, 0)
        guard status == 0 else { throw HapticFeedbackError.operation("MTActuatorActuate", status) }
    }

    func stop() throws {
        guard let actuator, let api else { return }
        self.actuator = nil
        let status = api.close(actuator)
        guard status == 0 else { throw HapticFeedbackError.operation("MTActuatorClose", status) }
    }

    isolated deinit {
        do { try stop() }
        catch { NSLog("EdgeControl haptics: %@", error.localizedDescription) }
    }
}

// Primary ABI and single-pulse example:
// https://gist.github.com/niw/b120b460e854ec10cefeeb60784f5dbb
// Waveforms 3/4/6 are Weak/Medium/Strong in HapticKey's HTKHapticFeedback.m:
// https://github.com/niw/HapticKey/blob/master/HapticKey/Sources/HTKHapticFeedback.m
private final class MultitouchHapticAPI {
    typealias Create = @convention(c) (UInt64) -> Unmanaged<CFTypeRef>?
    typealias Operation = @convention(c) (CFTypeRef) -> Int32
    typealias Actuate = @convention(c) (CFTypeRef, Int32, UInt32, Float32, Float32) -> Int32

    private let library: UnsafeMutableRawPointer
    let create: Create
    let open: Operation
    let close: Operation
    let actuate: Actuate

    init() throws {
        let path = try systemPrivateFrameworkPath("MultitouchSupport")
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw HapticFeedbackError.unavailable("MultitouchSupport is unavailable for haptic feedback")
        }
        self.library = library
        do {
            func symbol<T>(_ name: String, _: T.Type) throws -> T {
                guard let address = dlsym(library, name) else {
                    throw HapticFeedbackError.unavailable("MultitouchSupport: missing \(name)")
                }
                return unsafeBitCast(address, to: T.self)
            }
            create = try symbol("MTActuatorCreateFromDeviceID", Create.self)
            open = try symbol("MTActuatorOpen", Operation.self)
            close = try symbol("MTActuatorClose", Operation.self)
            actuate = try symbol("MTActuatorActuate", Actuate.self)
        } catch {
            dlclose(library)
            throw error
        }
    }

    deinit { dlclose(library) }
}
