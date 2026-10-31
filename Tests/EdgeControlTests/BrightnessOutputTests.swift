import Testing
@testable import EdgeControl

struct BrightnessOutputTests {
    @Test func choosesBuiltInDisplayInsteadOfFirstExternalDisplay() throws {
        #expect(try builtInDisplayID(in: [
            (id: 10, isBuiltIn: false, isActive: true),
            (id: 20, isBuiltIn: true, isActive: true),
        ]) == 20)
    }

    @Test func rejectsMissingOrAmbiguousBuiltInDisplay() {
        #expect(throws: BrightnessOutputError.self) { try builtInDisplayID(in: []) }
        #expect(throws: BrightnessOutputError.self) {
            try builtInDisplayID(in: [(id: 10, isBuiltIn: false, isActive: true)])
        }
        #expect(throws: BrightnessOutputError.self) {
            try builtInDisplayID(in: [
                (id: 10, isBuiltIn: true, isActive: true),
                (id: 20, isBuiltIn: true, isActive: false),
            ])
        }
    }

    @Test func rejectsInactiveBuiltInInsteadOfUsingExternalDisplay() {
        #expect(throws: BrightnessOutputError.self) {
            try builtInDisplayID(in: [
                (id: 10, isBuiltIn: true, isActive: false),
                (id: 20, isBuiltIn: false, isActive: true),
            ])
        }
    }
}
