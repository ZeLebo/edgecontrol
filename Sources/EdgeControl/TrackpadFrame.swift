struct TrackpadContact: Sendable, Equatable {
    let id: Int32
    let x: Double
    let y: Double
}
struct TrackpadFrame: Sendable, Equatable {
    let timestamp: Double
    let contacts: [TrackpadContact]
}
struct GestureUpdate: Sendable, Equatable {
    let isActive: Bool
    let percent: Int?
    static let inactive = GestureUpdate(isActive: false, percent: nil)
}
