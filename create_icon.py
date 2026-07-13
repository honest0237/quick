#!/usr/bin/env python3
"""Quick 앱 아이콘 생성 (⚡ 볼트 + 사각형)"""
import subprocess, os, tempfile

# SVG 아이콘
svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#4A90D9"/>
      <stop offset="100%" stop-color="#7B68EE"/>
    </linearGradient>
  </defs>
  <!-- 둥근 사각형 배경 -->
  <rect x="40" y="40" width="944" height="944" rx="200" fill="url(#bg)"/>
  <!-- 볼트 (⚡) -->
  <path d="M 580 120 L 340 540 L 480 540 L 440 900 L 700 460 L 550 460 Z"
        fill="white" stroke="none"/>
</svg>'''

tmpdir = tempfile.mkdtemp()
svg_path = os.path.join(tmpdir, "icon.svg")
iconset_dir = os.path.join(tmpdir, "AppIcon.iconset")
os.makedirs(iconset_dir)

with open(svg_path, "w") as f:
    f.write(svg)

# 각 크기별 PNG 생성
sizes = [
    (16, "16x16", 1), (32, "16x16", 2),
    (32, "32x32", 1), (64, "32x32", 2),
    (128, "128x128", 1), (256, "128x128", 2),
    (256, "256x256", 1), (512, "256x256", 2),
    (512, "512x512", 1), (1024, "512x512", 2),
]

for px, name, scale in sizes:
    suffix = f"@2x" if scale == 2 else ""
    filename = f"icon_{name}{suffix}.png"
    out = os.path.join(iconset_dir, filename)
    subprocess.run([
        "sips", "-s", "format", "png",
        "-z", str(px), str(px),
        svg_path, "--out", out
    ], capture_output=True)

# PNG로 대체 (sips는 SVG를 직접 못 읽으므로 rsvg-convert나 다른 방법 사용)
# 대신 CoreGraphics로 직접 그리기
script = f'''
import Cocoa

func createIcon(size: Int) -> NSImage {{
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)
    let r = s * 0.2 // corner radius

    // 배경 그라데이션
    let bgPath = CGPath(roundedRect: CGRect(x: s*0.04, y: s*0.04, width: s*0.92, height: s*0.92),
                         cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    let colors = [
        CGColor(red: 0.29, green: 0.56, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.48, green: 0.41, blue: 0.93, alpha: 1.0)
    ]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: colors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    ctx.resetClip()

    // 볼트
    let bolt = CGMutablePath()
    bolt.move(to: CGPoint(x: s*0.57, y: s*0.88))
    bolt.addLine(to: CGPoint(x: s*0.33, y: s*0.47))
    bolt.addLine(to: CGPoint(x: s*0.47, y: s*0.47))
    bolt.addLine(to: CGPoint(x: s*0.43, y: s*0.12))
    bolt.addLine(to: CGPoint(x: s*0.68, y: s*0.55))
    bolt.addLine(to: CGPoint(x: s*0.54, y: s*0.55))
    bolt.closeSubpath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(bolt)
    ctx.fillPath()

    img.unlockFocus()
    return img
}}

let iconsetDir = "{iconset_dir}"
let sizes: [(Int, String, Int)] = [
    (16, "16x16", 1), (32, "16x16", 2),
    (32, "32x32", 1), (64, "32x32", 2),
    (128, "128x128", 1), (256, "128x128", 2),
    (256, "256x256", 1), (512, "256x256", 2),
    (512, "512x512", 1), (1024, "512x512", 2),
]

for (px, name, scale) in sizes {{
    let img = createIcon(size: px)
    let suffix = scale == 2 ? "@2x" : ""
    let filename = "icon_\\(name)\\(suffix).png"
    let path = "\\(iconsetDir)/\\(filename)"

    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {{
        try? png.write(to: URL(fileURLWithPath: path))
    }}
}}
'''

# Swift 스크립트로 아이콘 생성
swift_path = os.path.join(tmpdir, "gen_icon.swift")
with open(swift_path, "w") as f:
    f.write(script)

subprocess.run(["swift", swift_path], capture_output=True)

# iconutil로 .icns 생성
dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "Resources", "AppIcon.icns")
result = subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", dest], capture_output=True, text=True)
if result.returncode == 0:
    print(f"아이콘 생성 완료: {dest}")
else:
    print(f"오류: {result.stderr}")
    # iconset 내용 확인
    for f in os.listdir(iconset_dir):
        size = os.path.getsize(os.path.join(iconset_dir, f))
        print(f"  {f}: {size} bytes")
