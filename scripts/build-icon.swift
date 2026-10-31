#!/usr/bin/env swift
import Foundation
import ImageIO

// ICNS stores PNG representations, including the four Retina sizes.
let representations: [(String, Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
    ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512),
]

func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "EdgeControlIcon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Usage: swift scripts/build-icon.swift INPUT.png OUTPUT.icns"])
    }
    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    var entries = Data()
    for (type, size) in representations {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        entries.append(Data(type.utf8))
        entries.append(bigEndian(png.length + 8))
        entries.append(png as Data)
    }
    var icon = Data("icns".utf8)
    icon.append(bigEndian(entries.count + 8))
    icon.append(entries)
    try icon.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
