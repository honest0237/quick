import AppKit
import CoreImage

// MARK: - 주석 모델

enum MarkupTool: String, CaseIterable {
    case rectangle
    case arrow
    case pixelate   // 민감정보 가리기(모자이크)
    case crop       // 자르기(주석이 아니라 영역 선택)

    var label: String {
        switch self {
        case .rectangle: return "사각형"
        case .arrow:     return "화살표"
        case .pixelate:  return "가리기"
        case .crop:      return "자르기"
        }
    }
}

/// 좌표는 모두 base 이미지의 **픽셀 공간**(원점 좌하단).
struct MarkupAnnotation {
    let tool: MarkupTool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var lineWidth: CGFloat

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

// MARK: - 렌더러 (순수 함수 — 헤드리스 검증 가능)

enum ImageMarkup {

    /// base 이미지의 픽셀 크기 (retina 대응).
    static func pixelSize(of image: NSImage) -> CGSize? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return CGSize(width: cg.width, height: cg.height)
    }

    /// base + 주석을 픽셀 해상도로 렌더링. cropRect(픽셀 좌표)가 있으면 마지막에 잘라냄.
    static func render(base: NSImage, annotations: [MarkupAnnotation], cropRect: CGRect? = nil) -> NSImage? {
        guard let baseCG = base.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = baseCG.width, h = baseCG.height

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: w, height: h)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        let full = NSRect(x: 0, y: 0, width: w, height: h)
        base.draw(in: full, from: .zero, operation: .copy, fraction: 1.0)

        for a in annotations {
            switch a.tool {
            case .pixelate:  drawPixelate(a, baseCG: baseCG, ctx: ctx)
            case .rectangle: drawRectangle(a)
            case .arrow:     drawArrow(a)
            case .crop:      break
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard var cg = rep.cgImage else { return nil }
        if let crop = cropRect {
            let clamped = crop.intersection(full)
            if clamped.width >= 1, clamped.height >= 1, let cropped = cg.cropping(to: clamped) {
                cg = cropped
            }
        }
        let outSize = NSSize(width: cg.width, height: cg.height)
        let outImage = NSImage(size: outSize)
        outImage.addRepresentation(NSBitmapImageRep(cgImage: cg))
        return outImage
    }

    // MARK: - 그리기 프리미티브

    private static func drawRectangle(_ a: MarkupAnnotation) {
        let path = NSBezierPath(rect: a.rect)
        path.lineWidth = a.lineWidth
        a.color.setStroke()
        path.stroke()
    }

    private static func drawArrow(_ a: MarkupAnnotation) {
        let p0 = a.start, p1 = a.end
        a.color.setStroke()
        a.color.setFill()

        let line = NSBezierPath()
        line.lineWidth = a.lineWidth
        line.lineCapStyle = .round
        line.move(to: p0)
        line.line(to: p1)
        line.stroke()

        // 화살촉
        let angle = atan2(p1.y - p0.y, p1.x - p0.x)
        let headLen = max(a.lineWidth * 4, 14)
        let spread = CGFloat.pi / 7
        let h1 = CGPoint(x: p1.x - headLen * cos(angle - spread),
                         y: p1.y - headLen * sin(angle - spread))
        let h2 = CGPoint(x: p1.x - headLen * cos(angle + spread),
                         y: p1.y - headLen * sin(angle + spread))
        let head = NSBezierPath()
        head.move(to: p1)
        head.line(to: h1)
        head.line(to: h2)
        head.close()
        head.fill()
    }

    private static func drawPixelate(_ a: MarkupAnnotation, baseCG: CGImage, ctx: NSGraphicsContext) {
        let region = a.rect.integral
        guard region.width >= 2, region.height >= 2 else { return }

        let ci = CIImage(cgImage: baseCG)
        let scale = max(min(region.width, region.height) / 6.0, 8.0)
        guard let filter = CIFilter(name: "CIPixellate") else { return }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: region.midX, y: region.midY), forKey: kCIInputCenterKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)

        let ciCtx = CIContext(options: nil)
        guard let output = filter.outputImage,
              let pixCG = ciCtx.createCGImage(output, from: ci.extent) else { return }

        // 전체 픽셀화 이미지를 그리되 선택 영역으로 클립 → 좌표계 일치(원점 좌하단)로 정확한 위치에 합성
        ctx.saveGraphicsState()
        NSBezierPath(rect: region).addClip()
        ctx.cgContext.draw(pixCG, in: CGRect(x: 0, y: 0, width: baseCG.width, height: baseCG.height))
        ctx.restoreGraphicsState()
    }
}
