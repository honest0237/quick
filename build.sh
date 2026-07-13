#!/bin/bash
set -e

# ─────────────────────────────────────────
# ScreenCapture 빌드 스크립트
# 사용법: ./build.sh [appstore|direct]
# ─────────────────────────────────────────

BUILD_TYPE="${1:-direct}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
RESOURCES_DIR="$PROJECT_DIR/Resources"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="Quick"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "🔨 Building ScreenCapture ($BUILD_TYPE)..."

# 빌드 디렉토리 생성
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 소스 파일 수집 (공백 안전)
SWIFT_FILES=()
while IFS= read -r -d '' file; do
    SWIFT_FILES+=("$file")
done < <(find "$SOURCES_DIR" -name "*.swift" -print0 | sort -z)

echo "📝 Source files:"
for f in "${SWIFT_FILES[@]}"; do echo "   $(basename "$f")"; done

# 컴파일 플래그
COMPILE_FLAGS=(
    -parse-as-library
    -O
    -framework SwiftUI
    -framework AppKit
    -framework CoreGraphics
    -framework Carbon
    -framework Vision
    -target arm64-apple-macos13.0
    -o "$BUILD_DIR/$APP_NAME"
)

# App Store vs Direct 빌드 분기
if [ "$BUILD_TYPE" = "appstore" ]; then
    COMPILE_FLAGS+=(-D APPSTORE)
    ENTITLEMENTS="$RESOURCES_DIR/ScreenCapture.entitlements"
    echo "📦 Build type: App Store (Sandbox enabled)"
else
    ENTITLEMENTS="$RESOURCES_DIR/DirectSale.entitlements"
    echo "📦 Build type: Direct Sale (No sandbox)"
fi

# 컴파일
echo "⚙️  Compiling..."
swiftc "${COMPILE_FLAGS[@]}" "${SWIFT_FILES[@]}"

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed!"
    exit 1
fi

echo "✅ Compilation successful"

# .app 번들 생성
echo "📁 Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 바이너리 복사
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist 복사
cp "$RESOURCES_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# PkgInfo 생성
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Entitlements 복사
cp "$ENTITLEMENTS" "$APP_BUNDLE/Contents/Resources/entitlements.plist"

# 앱 아이콘 복사
if [ -f "$RESOURCES_DIR/AppIcon.icns" ]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "🎨 App icon included"
fi

echo "✅ App bundle created: $APP_BUNDLE"

# 크기 확인
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "📊 App size: $APP_SIZE"

echo ""
echo "🚀 To run: open \"$APP_BUNDLE\""
echo "   Or: \"$APP_BUNDLE/Contents/MacOS/$APP_NAME\""
