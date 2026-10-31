import CoreFoundation
import Darwin
import Foundation

@MainActor
final class TrackpadInput {
    var onFrame: ((TrackpadFrame) -> Void)?
    var onError: ((String) -> Void)?
    private(set) var isRunning = false

    private var api: MultitouchAPI?
    private var devices: CFArray?
    private var device: UnsafeMutableRawPointer?
    private var generation: UInt64 = 0

    func start() throws {
        guard !isRunning else { return }
        let api = try self.api ?? MultitouchAPI()
        self.api = api
        guard let list = api.createList()?.takeRetainedValue() else {
            throw TrackpadInputError.unavailable("Could not enumerate trackpads")
        }
        let available = (0..<CFArrayGetCount(list)).compactMap { index -> UnsafeMutableRawPointer? in
            guard let value = CFArrayGetValueAtIndex(list, index) else { return nil }
            return UnsafeMutableRawPointer(mutating: value)
        }
        let properties = available.map {
            (isBuiltIn: api.isBuiltIn($0), isOpaqueSurface: api.isOpaqueSurface($0))
        }
        let selected = available[try builtInTrackpadIndex(in: properties)]

        generation &+= 1
        let currentGeneration = generation
        let session = ContactSession { [weak self] result in
            guard let self, self.isRunning, self.generation == currentGeneration else { return }
            switch result {
            case .success(let frame):
                self.onFrame?(frame)
            case .failure(let error):
                self.stop()
                self.onError?(error.localizedDescription)
            }
        }
        devices = list
        device = selected
        isRunning = true
        ContactRegistry.shared.install(session, for: selected)
        api.register(selected, contactFrameCallback)
        let status = api.start(selected, 0)
        guard status == 0, api.isRunning(selected) else {
            stop()
            throw TrackpadInputError.unavailable("Could not start the trackpad (\(status))")
        }
    }

    func stop() {
        generation &+= 1
        isRunning = false
        if let device, let api {
            ContactRegistry.shared.remove(device)
            api.unregister(device, contactFrameCallback)
            _ = api.stop(device)
        }
        device = nil
        devices = nil
    }

    isolated deinit { stop() }
}

func builtInTrackpadIndex(in devices: [(isBuiltIn: Bool, isOpaqueSurface: Bool)]) throws -> Int {
    // Built-in trackpads may report opaque=false; opacity does not identify the device type.
    let candidates = devices.indices.filter { devices[$0].isBuiltIn }
    guard candidates.count == 1, let selected = candidates.first else {
        throw TrackpadInputError.unavailable(
            candidates.isEmpty ? "Built-in trackpad not found" : "Multiple built-in trackpad sensors found"
        )
    }
    return selected
}

enum TrackpadInputError: LocalizedError, Sendable {
    case unavailable(String)
    case invalidFrame

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .invalidFrame: "Invalid trackpad frame: check MultitouchSupport compatibility"
        }
    }
}

// The reverse-engineered ABI is described by OpenMultitouchSupport's primary header:
// https://github.com/Kyome22/OpenMultitouchSupport/blob/main/Framework/OpenMultitouchSupportXCF/OpenMTInternal.h
// shortcut: the private 96-byte contact ABI must be rechecked after incompatible macOS updates.
private typealias ContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32
) -> Void

private let contactFrameCallback: ContactCallback = { device, buffer, count, _, _ in
    guard let device, let session = ContactRegistry.shared.session(for: device) else { return }
    let result = decodeTrackpadContacts(buffer, count: count, timestamp: ProcessInfo.processInfo.systemUptime)
    DispatchQueue.main.async { session.deliver(result) }
}

func decodeTrackpadContacts(
    _ buffer: UnsafeRawPointer?, count: Int32, timestamp: Double
) -> Result<TrackpadFrame, TrackpadInputError> {
    guard (0...32).contains(count), count == 0 || buffer != nil else { return .failure(.invalidFrame) }
    var contacts: [TrackpadContact] = []
    var identifiers = Set<Int32>()
    for index in 0..<Int(count) {
        guard let raw = buffer?.advanced(by: index * 96) else { return .failure(.invalidFrame) }
        let state = raw.loadUnaligned(fromByteOffset: 20, as: Int32.self)
        guard (0...7).contains(state) else { return .failure(.invalidFrame) }
        // Making/touching includes stationary contacts; hover and lift-off are not physical touches.
        guard state == 3 || state == 4 else { continue }
        let id = raw.loadUnaligned(fromByteOffset: 16, as: Int32.self)
        let x = Double(raw.loadUnaligned(fromByteOffset: 32, as: Float.self))
        let y = Double(raw.loadUnaligned(fromByteOffset: 36, as: Float.self))
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y),
              identifiers.insert(id).inserted else { return .failure(.invalidFrame) }
        contacts.append(TrackpadContact(id: id, x: x, y: y))
    }
    return .success(TrackpadFrame(timestamp: timestamp, contacts: contacts))
}

private final class ContactSession: Sendable {
    let deliver: @MainActor @Sendable (Result<TrackpadFrame, TrackpadInputError>) -> Void

    init(deliver: @escaping @MainActor @Sendable (Result<TrackpadFrame, TrackpadInputError>) -> Void) {
        self.deliver = deliver
    }
}

// Access from the native callback is protected by the lock; sessions carry immutable closures.
private final class ContactRegistry: @unchecked Sendable {
    static let shared = ContactRegistry()
    private let lock = NSLock()
    private var sessions: [UInt: ContactSession] = [:]

    func install(_ session: ContactSession, for device: UnsafeMutableRawPointer) {
        lock.withLock { sessions[UInt(bitPattern: device)] = session }
    }

    func remove(_ device: UnsafeMutableRawPointer) {
        _ = lock.withLock { sessions.removeValue(forKey: UInt(bitPattern: device)) }
    }

    func session(for device: UnsafeMutableRawPointer) -> ContactSession? {
        lock.withLock { sessions[UInt(bitPattern: device)] }
    }
}

private final class MultitouchAPI {
    typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias DeviceFlag = @convention(c) (UnsafeMutableRawPointer) -> Bool
    typealias Register = @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
    typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Int32

    private let library: UnsafeMutableRawPointer
    let createList: CreateList
    let isBuiltIn: DeviceFlag
    let isOpaqueSurface: DeviceFlag
    let isRunning: DeviceFlag
    let register: Register
    let unregister: Register
    let start: Start
    let stop: Stop

    init() throws {
        let path = try systemPrivateFrameworkPath("MultitouchSupport")
        guard let library = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw TrackpadInputError.unavailable("MultitouchSupport is unavailable")
        }
        self.library = library
        do {
            func symbol<T>(_ name: String, _: T.Type) throws -> T {
                guard let pointer = dlsym(library, name) else {
                    throw TrackpadInputError.unavailable("MultitouchSupport: missing \(name)")
                }
                return unsafeBitCast(pointer, to: T.self)
            }
            createList = try symbol("MTDeviceCreateList", CreateList.self)
            isBuiltIn = try symbol("MTDeviceIsBuiltIn", DeviceFlag.self)
            isOpaqueSurface = try symbol("MTDeviceIsOpaqueSurface", DeviceFlag.self)
            isRunning = try symbol("MTDeviceIsRunning", DeviceFlag.self)
            register = try symbol("MTRegisterContactFrameCallback", Register.self)
            unregister = try symbol("MTUnregisterContactFrameCallback", Register.self)
            start = try symbol("MTDeviceStart", Start.self)
            stop = try symbol("MTDeviceStop", Stop.self)
        } catch {
            dlclose(library)
            throw error
        }
    }

    // Keep the framework mapped until process exit: unregister/stop does not document
    // whether an in-flight callback has finished unwinding through private framework code.
}
