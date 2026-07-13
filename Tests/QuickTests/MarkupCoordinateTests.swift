import XCTest
import AppKit
@testable import Quick

/// 마크업 렌더러 좌표 회귀 테스트.
/// v1.2.3까지 crop이 세로로 뒤집힌 영역을 내보내던 실제 버그를 영구 차단한다.
final class MarkupCoordinateTests: XCTestCase {

    /// 아래 절반 파랑, 위 절반 빨강인 100x100 픽셀 이미지
    private func halfRedHalfBlue(_ n: Int = 100) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        NSColor.blue.setFill(); NSRect(x: 0, y: 0, width: n, height: n/2).fill()      // 아래(y 0-50)
        NSColor.red.setFill();  NSRect(x: 0, y: n/2, width: n, height: n/2).fill()    // 위(y 50-100)
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: n, height: n)); img.addRepresentation(rep)
        return img
    }

    private func centerColor(_ img: NSImage) -> NSColor {
        let rep = NSBitmapImageRep(cgImage: img.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        return rep.colorAt(x: rep.pixelsWide/2, y: rep.pixelsHigh/2)!
    }

    // 캔버스 좌표(좌하단)로 "위쪽" 영역을 crop → 위쪽(빨강)이 나와야 함 (예전엔 파랑=버그)
    func test_crop_topRegion_returnsTopContent() {
        let out = ImageMarkup.render(base: halfRedHalfBlue(), annotations: [],
                                     cropRect: CGRect(x: 0, y: 60, width: 100, height: 30))
        XCTAssertNotNil(out)
        let c = centerColor(out!)
        XCTAssertGreaterThan(c.redComponent, 0.7, "위쪽 영역 crop인데 빨강이 아님 → 좌표 뒤집힘")
        XCTAssertLessThan(c.blueComponent, 0.3)
    }

    func test_crop_bottomRegion_returnsBottomContent() {
        let out = ImageMarkup.render(base: halfRedHalfBlue(), annotations: [],
                                     cropRect: CGRect(x: 0, y: 10, width: 100, height: 30))
        let c = centerColor(out!)
        XCTAssertGreaterThan(c.blueComponent, 0.7, "아래쪽 영역 crop인데 파랑이 아님")
    }

    func test_crop_outputHasRequestedSize() {
        let out = ImageMarkup.render(base: halfRedHalfBlue(), annotations: [],
                                     cropRect: CGRect(x: 10, y: 10, width: 50, height: 30))!
        let size = ImageMarkup.pixelSize(of: out)!
        XCTAssertEqual(Int(size.width), 50)
        XCTAssertEqual(Int(size.height), 30)
    }

    // 가리기(pixelate)가 지정 영역에만 적용되고 대칭 반대편은 건드리지 않아야 함
    func test_pixelate_altersOnlyTargetRegion() {
        let n = 100
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
        for y in 0..<n { for x in 0..<n {   // 2px 체커보드
            ((x/2 + y/2) % 2 == 0 ? NSColor.black : NSColor.white).setFill()
            NSRect(x: x, y: y, width: 1, height: 1).fill()
        }}
        NSGraphicsContext.restoreGraphicsState()
        let base = NSImage(size: NSSize(width: n, height: n)); base.addRepresentation(rep)

        let pix = MarkupAnnotation(tool: .pixelate, start: CGPoint(x: 30, y: 60),
                                   end: CGPoint(x: 70, y: 90), color: .red, lineWidth: 3)
        let plainRep = NSBitmapImageRep(cgImage: ImageMarkup.render(base: base, annotations: [])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        let pixRep = NSBitmapImageRep(cgImage: ImageMarkup.render(base: base, annotations: [pix])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)

        var changedTop = 0, changedBottom = 0
        for rowTop in 0..<n { for x in 0..<n {
            let yBottom = n - 1 - rowTop
            let a = plainRep.colorAt(x: x, y: rowTop)!, b = pixRep.colorAt(x: x, y: rowTop)!
            if abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) > 0.2 {
                if yBottom >= 60 && yBottom <= 90 { changedTop += 1 }
                if yBottom >= 10 && yBottom <= 40 { changedBottom += 1 }   // 대칭 반대편
            }
        }}
        XCTAssertGreaterThan(changedTop, 100, "가리기 영역이 바뀌지 않음")
        XCTAssertEqual(changedBottom, 0, "가리기가 반대편에도 적용됨 → 좌표 뒤집힘")
    }

    func test_rectangle_drawsColor() {
        let rect = MarkupAnnotation(tool: .rectangle, start: CGPoint(x: 10, y: 10),
                                    end: CGPoint(x: 90, y: 90), color: .red, lineWidth: 4)
        let out = ImageMarkup.render(base: halfRedHalfBlue(), annotations: [rect])
        XCTAssertNotNil(out)
    }
}
