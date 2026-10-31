import Foundation

func systemPrivateFrameworkPath(_ name: String) throws -> String {
    guard let library = FileManager.default.urls(for: .libraryDirectory, in: .systemDomainMask).first else {
        throw CocoaError(.fileNoSuchFile)
    }
    return library.appendingPathComponent("PrivateFrameworks", isDirectory: true)
        .appendingPathComponent("\(name).framework", isDirectory: true)
        .appendingPathComponent(name).path
}
