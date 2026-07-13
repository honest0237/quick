import AppKit

// MARK: - 마크업 에디터 창

@MainActor
final class MarkupEditorWindowController: NSWindowController, NSWindowDelegate {
    private static var openControllers: Set<MarkupEditorWindowController> = []

    private let sourceItem: ScreenshotItem
    private let canvas: MarkupCanvasView
    private let toolSelector: NSSegmentedControl
    private let colorWell: NSColorWell

    static func present(item: ScreenshotItem) {
        guard let image = item.fullImage else { NSSound(named: "Basso")?.play(); return }
        let wc = MarkupEditorWindowController(item: item, image: image)
        openControllers.insert(wc)
        wc.showWindow(nil)
        wc.window?.center()
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(item: ScreenshotItem, image: NSImage) {
        self.sourceItem = item
        self.canvas = MarkupCanvasView(image: image)

        // 표시 크기: 이미지 비율 유지, 화면의 80% 이내
        let pxSize = ImageMarkup.pixelSize(of: image) ?? image.size
        let screen = (NSScreen.main ?? NSScreen.screens.first!).visibleFrame
        let maxW = screen.width * 0.8, maxH = screen.height * 0.8 - 60
        let scale = min(maxW / pxSize.width, maxH / pxSize.height, 1.5)
        let canvasSize = NSSize(width: max(pxSize.width * scale, 320),
                                height: max(pxSize.height * scale, 200))

        toolSelector = NSSegmentedControl(labels: MarkupTool.allCases.map { $0.label },
                                          trackingMode: .selectOne, target: nil, action: nil)
        toolSelector.selectedSegment = MarkupTool.allCases.firstIndex(of: .pixelate) ?? 0
        colorWell = NSColorWell()
        colorWell.color = .systemRed

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height + 48),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "편집 — \(item.filename)"
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        canvas.tool = .pixelate
        canvas.color = colorWell.color
        toolSelector.target = self
        toolSelector.action = #selector(toolChanged)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)

        window.contentView = buildContentView(canvasSize: canvasSize)
        canvas.frame = NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContentView(canvasSize: NSSize) -> NSView {
        func button(_ title: String, _ selector: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: selector)
            b.bezelStyle = .rounded
            return b
        }

        let toolbar = NSStackView(views: [
            toolSelector,
            colorWell,
            NSView(),  // spacer
            button("되돌리기", #selector(undo)),
            button("복사", #selector(copyResult)),
            button("저장", #selector(saveResult)),
        ])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let container = NSStackView(views: [toolbar, canvas])
        container.orientation = .vertical
        container.spacing = 0
        container.distribution = .fill
        container.alignment = .width
        toolbar.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return container
    }

    @objc private func toolChanged() {
        canvas.tool = MarkupTool.allCases[toolSelector.selectedSegment]
    }

    @objc private func colorChanged() {
        canvas.color = colorWell.color
    }

    @objc private func undo() { canvas.undoLast() }

    @objc private func copyResult() {
        guard let out = canvas.exportImage() else { NSSound(named: "Basso")?.play(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([out])
        NSSound(named: "Glass")?.play()
    }

    @objc private func saveResult() {
        let format = AppSettings.shared.format   // 설정된 저장 형식(PNG/JPEG) 반영
        guard let out = canvas.exportImage(),
              let tiff = out.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            NSSound(named: "Basso")?.play(); return
        }
        let data: Data?
        switch format {
        case .png:  data = bitmap.representation(using: .png, properties: [:])
        case .jpeg: data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        }
        guard let imageData = data else { NSSound(named: "Basso")?.play(); return }

        let dir = AppSettings.shared.saveDirectoryURL
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        // "Markup" 이름은 스크린샷 감시 패턴과 겹치지 않아 이중 추가되지 않음
        let url = dir.appendingPathComponent("Quick_Markup_\(df.string(from: Date())).\(format.fileExtension)")
        do {
            try imageData.write(to: url)
            ScreenshotStore.shared.addFile(fileURL: url)   // 선반에 편집본 추가
            NSSound(named: "Glass")?.play()
            window?.close()
        } catch {
            NSSound(named: "Basso")?.play()
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.remove(self)
    }
}

// MARK: - 캔버스 (그리기 + 실시간 미리보기)

final class MarkupCanvasView: NSView {
    let image: NSImage
    let pixelSize: CGSize

    var tool: MarkupTool = .pixelate
    var color: NSColor = .systemRed { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 4

    private var annotations: [MarkupAnnotation] = []
    private var pendingCrop: CGRect?          // 픽셀 좌표
    private var dragStart: CGPoint?           // 픽셀 좌표
    private var dragCurrent: CGPoint?         // 픽셀 좌표
    private var composite: NSImage            // 확정 주석까지 렌더된 캐시

    init(image: NSImage) {
        self.image = image
        self.pixelSize = ImageMarkup.pixelSize(of: image) ?? image.size
        self.composite = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    // MARK: 좌표 매핑

    /// 이미지가 뷰 안에 aspect-fit 되는 사각형(뷰 좌표, 원점 좌하단)
    private var imageRect: CGRect {
        let vs = bounds.size
        guard vs.width > 0, vs.height > 0 else { return bounds }
        let scale = min(vs.width / pixelSize.width, vs.height / pixelSize.height)
        let w = pixelSize.width * scale, h = pixelSize.height * scale
        return CGRect(x: (vs.width - w) / 2, y: (vs.height - h) / 2, width: w, height: h)
    }

    private func toPixel(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        let x = (p.x - r.minX) / r.width * pixelSize.width
        let y = (p.y - r.minY) / r.height * pixelSize.height
        return CGPoint(x: min(max(x, 0), pixelSize.width), y: min(max(y, 0), pixelSize.height))
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let r = imageRect
        return CGPoint(x: r.minX + p.x / pixelSize.width * r.width,
                       y: r.minY + p.y / pixelSize.height * r.height)
    }

    private func toViewRect(_ rect: CGRect) -> CGRect {
        let o = toView(rect.origin)
        let r = imageRect
        return CGRect(x: o.x, y: o.y,
                      width: rect.width / pixelSize.width * r.width,
                      height: rect.height / pixelSize.height * r.height)
    }

    // MARK: 마우스

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStart = toPixel(p)
        dragCurrent = dragStart
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragCurrent = toPixel(p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragCurrent = nil; needsDisplay = true }
        guard let s = dragStart, let e = dragCurrent else { return }
        let ann = MarkupAnnotation(tool: tool, start: s, end: e, color: color, lineWidth: lineWidth)
        // 너무 작은 제스처는 무시
        guard ann.rect.width >= 3 || ann.rect.height >= 3 else { return }

        if tool == .crop {
            pendingCrop = ann.rect
        } else {
            annotations.append(ann)
            rebuildComposite()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undoLast()
        } else {
            super.keyDown(with: event)
        }
    }

    func undoLast() {
        if pendingCrop != nil { pendingCrop = nil; needsDisplay = true; return }
        if !annotations.isEmpty { annotations.removeLast(); rebuildComposite() }
    }

    private func rebuildComposite() {
        composite = ImageMarkup.render(base: image, annotations: annotations) ?? image
        needsDisplay = true
    }

    func exportImage() -> NSImage? {
        ImageMarkup.render(base: image, annotations: annotations, cropRect: pendingCrop)
    }

    // MARK: 그리기

    override func draw(_ dirtyRect: NSRect) {
        let r = imageRect
        composite.draw(in: r, from: .zero, operation: .copy, fraction: 1.0)

        // 드래그 중 미리보기
        if let s = dragStart, let e = dragCurrent {
            let ann = MarkupAnnotation(tool: tool, start: s, end: e, color: color, lineWidth: lineWidth)
            drawPreview(ann)
        }

        // 자르기 예정 영역: 바깥 어둡게
        if let crop = pendingCrop {
            let cv = toViewRect(crop)
            NSColor.black.withAlphaComponent(0.45).setFill()
            let outside = NSBezierPath(rect: r)
            outside.append(NSBezierPath(rect: cv))
            outside.windingRule = .evenOdd
            outside.fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: cv); border.lineWidth = 1; border.stroke()
        }
    }

    private func drawPreview(_ a: MarkupAnnotation) {
        let vr = toViewRect(a.rect)
        switch a.tool {
        case .rectangle:
            a.color.setStroke()
            let p = NSBezierPath(rect: vr); p.lineWidth = a.lineWidth; p.stroke()
        case .crop:
            NSColor.white.setStroke()
            let p = NSBezierPath(rect: vr); p.lineWidth = 1
            p.setLineDash([6, 4], count: 2, phase: 0); p.stroke()
        case .pixelate:
            NSColor.black.withAlphaComponent(0.35).setFill()
            NSBezierPath(rect: vr).fill()
        case .arrow:
            a.color.setStroke()
            let p = NSBezierPath()
            p.lineWidth = a.lineWidth; p.lineCapStyle = .round
            p.move(to: toView(a.start)); p.line(to: toView(a.end)); p.stroke()
        }
    }
}
