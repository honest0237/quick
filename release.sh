#!/bin/bash
# ─────────────────────────────────────────────────────────────
# Quick 원클릭 배포 스크립트
#   빌드 → DMG 재서명·패키징 → git 커밋·푸시 → GitHub 릴리스
#
# 사용법:
#   ./release.sh                 현재 Info.plist 버전으로 배포 (2·3단계)
#   ./release.sh 1.2.1           버전 1.2.1로 올려서 배포 (1·2·3단계)
#   ./release.sh 1.2.1 notes.md  릴리스 노트를 notes.md 에서 읽음
#                                (생략 시 직전 태그 이후 커밋으로 자동 생성)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

REPO="honest0237/quick"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$PROJECT_DIR/Resources/Info.plist"
APP="$PROJECT_DIR/build/Quick.app"
PB=/usr/libexec/PlistBuddy

# ── 공증 준비 (나중에 Apple Developer 계정 생기면 아래 2개만 설정하면 자동 실행) ──
#   export QUICK_SIGN_ID="Developer ID Application: 이름 (TEAMID)"
#   export QUICK_NOTARY_PROFILE="notary"   # xcrun notarytool store-credentials 로 만든 키체인 프로파일
# 둘 다 비어있으면 지금처럼 ad-hoc 서명(지인 배포용, xattr -cr 필요).
SIGN_ID="${QUICK_SIGN_ID:-}"
NOTARY_PROFILE="${QUICK_NOTARY_PROFILE:-}"

step() { printf "\n\033[1;34m▶ %s\033[0m\n" "$1"; }
die()  { printf "\033[1;31m✖ %s\033[0m\n" "$1" >&2; exit 1; }

# 방금 빌드·서명한 앱을 이 컴퓨터의 /Applications 에 설치하고 실행.
# (릴리스 성공 후 호출 — 실패해도 릴리스는 유지되므로 스크립트를 중단하지 않음)
install_locally() {
  step "로컬 설치 (내 컴퓨터 최신화)"
  # 실행 중인 모든 Quick 인스턴스 종료
  pkill -f "Quick.app/Contents/MacOS/Quick" 2>/dev/null || true
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "Quick.app/Contents/MacOS/Quick" >/dev/null || break
    sleep 0.3
  done
  local DEST="/Applications/Quick.app"
  if rm -rf "$DEST" 2>/dev/null && cp -R "$STAGE/root/Quick.app" "$DEST" 2>/dev/null; then
    xattr -cr "$DEST" 2>/dev/null || true
    open "$DEST" 2>/dev/null || true
    echo "  → /Applications/Quick.app ($VERSION) 설치 · 실행"
  else
    echo "  ⚠ /Applications 설치 실패(권한 등). DMG로 수동 설치: $DMG_PATH"
  fi
}

# ── 0) 사전 점검 ─────────────────────────────────────────────
command -v gh >/dev/null || die "gh CLI가 필요합니다 (brew install gh)"
gh auth status >/dev/null 2>&1 || die "gh 인증이 필요합니다 (gh auth login)"
[ -f "$PLIST" ] || die "Info.plist를 찾을 수 없습니다: $PLIST"

ARG_VERSION="${1:-}"
NOTES_FILE="${2:-}"

# ── 1) 버전 결정 (인자 있으면 상향, 없으면 현재 값 사용) ──────
if [ -n "$ARG_VERSION" ]; then
  VERSION="${ARG_VERSION#v}"                       # 앞의 v 제거
  echo "$VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){1,2}$' || die "버전 형식 오류: $VERSION (예: 1.2.1)"
  CUR_BUILD=$($PB -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo 0)
  $PB -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  $PB -c "Set :CFBundleVersion $((CUR_BUILD + 1))" "$PLIST"
  step "버전 상향 → $VERSION (build $((CUR_BUILD + 1)))"
else
  VERSION=$($PB -c "Print :CFBundleShortVersionString" "$PLIST")
  step "현재 버전으로 배포 → $VERSION"
fi

TAG="v$VERSION"
DMG_NAME="Quick_${VERSION}_universal.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

# 태그 중복 방지
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  die "릴리스 $TAG 가 이미 존재합니다. 버전을 올리세요."
fi

# ── 2) 테스트 게이트 (빨간불이면 배포 중단) ──────────────────
step "테스트 (swift test)"
if command -v swift >/dev/null 2>&1; then
  ( cd "$PROJECT_DIR" && swift test 2>&1 | tail -3 ) || die "테스트 실패 — 배포 중단"
else
  echo "  ⚠ swift 없음 — 테스트 건너뜀"
fi

# ── 3) 빌드 ──────────────────────────────────────────────────
step "빌드"
"$PROJECT_DIR/build.sh" direct >/dev/null
[ -d "$APP" ] || die "빌드 산출물이 없습니다: $APP"

# ── 3) DMG 재서명 · 패키징 ───────────────────────────────────
step "DMG 패키징"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/root"
cp -R "$APP" "$STAGE/root/Quick.app"
chmod -R u+rwX,go+rX,go-w "$STAGE/root/Quick.app"
chmod 755 "$STAGE/root/Quick.app/Contents/MacOS/Quick"
xattr -cr "$STAGE/root/Quick.app"
ENT="$STAGE/root/Quick.app/Contents/Resources/entitlements.plist"
if [ -n "$SIGN_ID" ]; then
  # 정식 서명 (Developer ID) — 공증 가능
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" --entitlements "$ENT" "$STAGE/root/Quick.app"
  echo "  → Developer ID 서명: $SIGN_ID"
else
  # ad-hoc 서명 (지인 배포용, 받는 사람이 xattr -cr 필요)
  codesign --force --deep --sign - --entitlements "$ENT" "$STAGE/root/Quick.app"
fi
codesign --verify --deep --strict "$STAGE/root/Quick.app" || die "서명 검증 실패"
ln -sf /Applications "$STAGE/root/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "Quick $VERSION" -srcfolder "$STAGE/root" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG_PATH" >/dev/null
echo "  → $DMG_NAME ($(du -h "$DMG_PATH" | cut -f1))"

# (선택) 공증 + staple — SIGN_ID 와 NOTARY_PROFILE 둘 다 설정된 경우에만
if [ -n "$SIGN_ID" ] && [ -n "$NOTARY_PROFILE" ]; then
  step "공증 (notarize + staple)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  echo "  → 공증 완료 (경고 없이 더블클릭 설치 가능)"
fi

# ── 4) 릴리스 노트 준비 ──────────────────────────────────────
step "릴리스 노트 준비"
NOTES_TMP="$(mktemp)"
trap 'rm -rf "$STAGE" "$NOTES_TMP"' EXIT
if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then
  cat "$NOTES_FILE" > "$NOTES_TMP"
  echo "  → 파일에서: $NOTES_FILE"
else
  git -C "$PROJECT_DIR" fetch --tags --quiet 2>/dev/null || true   # gh가 서버에 만든 태그도 반영
  LAST_TAG=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "")
  {
    echo "## Quick $VERSION"
    echo ""
    if [ -n "$LAST_TAG" ]; then
      # 직전 태그 이후 커밋 (Co-Authored / Release 커밋은 제외)
      git -C "$PROJECT_DIR" log "${LAST_TAG}..HEAD" --pretty="- %s" \
        | grep -vE "Co-Authored-By|^- Release v" || echo "- 변경 사항"
    else
      echo "- 첫 릴리스"
    fi
    echo ""
    echo "### 설치"
    echo "1. \`$DMG_NAME\` 다운로드 후 Quick.app을 Applications로 드래그"
    echo "2. 처음 열 때 \"손상되어 열 수 없습니다\"가 뜨면 터미널에서:"
    echo '   ```'
    echo "   xattr -cr /Applications/Quick.app"
    echo '   ```'
    echo "   (Apple Silicon 전용 · 공증 전이라 뜨는 경고입니다)"
  } > "$NOTES_TMP"
  echo "  → git 커밋에서 자동 생성 (${LAST_TAG:-첫 릴리스} 이후)"
fi

# ── 5) git 커밋 · 푸시 (릴리스 태그가 이 커밋을 가리키도록) ───
step "git 커밋 · 푸시"
if [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]; then
  git -C "$PROJECT_DIR" add -A
  git -C "$PROJECT_DIR" commit -q -m "Release $TAG"
  echo "  → 커밋: Release $TAG"
fi
git -C "$PROJECT_DIR" push -q origin HEAD
echo "  → 푸시 완료"

# ── 6) GitHub 릴리스 생성 (DMG 첨부) ─────────────────────────
step "GitHub 릴리스 생성"
gh release create "$TAG" "$DMG_PATH" \
  --repo "$REPO" \
  --title "Quick $VERSION" \
  --notes-file "$NOTES_TMP"

# ── 7) 내 컴퓨터 최신화 (QUICK_NO_INSTALL=1 로 건너뛰기 가능) ─
if [ "${QUICK_NO_INSTALL:-}" != "1" ]; then
  install_locally
fi

printf "\n\033[1;32m✅ 배포 완료: %s\033[0m\n" "$TAG"
echo "   https://github.com/$REPO/releases/tag/$TAG"
echo "   → 구버전 사용자에게 인앱 업데이트 알림이 표시됩니다."
