import AppKit
import Testing
@testable import EdgeControl

@MainActor
struct HUDGeometryTests {
    @Test func pixelsFollowTheLatestLevelWithoutAdvancingTheRunLoop() throws {
        let meter = HUDMeterView(frame: NSRect(x: 0, y: 0, width: 150, height: 8))
        meter.setLevel(20)
        #expect(try alpha(at: 100, in: meter) < 0.3)
        meter.setLevel(90)
        #expect(try alpha(at: 100, in: meter) > 0.8)
        meter.setLevel(10)
        #expect(try alpha(at: 100, in: meter) < 0.3)
    }

    @Test func changingLevelReplacesTheRenderedGeometryImmediately() {
        let meter = HUDMeterView(frame: NSRect(x: 0, y: 0, width: 150, height: 8))
        meter.setLevel(20)
        #expect(meter.filledRect.width == 30)
        meter.setLevel(90)
        #expect(meter.percent == 90)
        #expect(meter.filledRect.width == 135)
        meter.setLevel(10)
        #expect(meter.filledRect.width == 15)
    }

    @Test func endpointsUseTheEntireTrackAndNoIntermediateState() {
        let meter = HUDMeterView(frame: NSRect(x: 0, y: 0, width: 200, height: 8))
        meter.setLevel(100)
        #expect(meter.filledRect == meter.bounds)
        meter.setLevel(0)
        #expect(meter.filledRect.width == 0)
        meter.frame.size.width = 300
        meter.setLevel(50)
        #expect(meter.filledRect.width == 150)
    }

    private func alpha(at x: Int, in meter: HUDMeterView) throws -> CGFloat {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 150, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.clear(meter.bounds)
        let appearance = try #require(NSAppearance(named: .aqua))
        appearance.performAsCurrentDrawingAppearance { meter.draw(meter.bounds) }
        return try #require(bitmap.colorAt(x: x, y: 4)).alphaComponent
    }
}
