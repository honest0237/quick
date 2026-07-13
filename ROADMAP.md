# Quick — 고도화 로드맵

> macOS 메뉴바 "스크린샷 선반(shelf)" 유틸리티
> 소스: `creative_tools/screen_capture/swift/` (SwiftPM 아님 — `build.sh`로 `swiftc` 직접 빌드)
> 배포본: `apps/quick_app 1/quick_app/Quick-배포/Quick-Swift.app`
> 최종 정리: 2026-07-13

---

## 0. 현재 상태 (코드 검증 완료)

| 영역 | 현황 | 파일 |
|------|------|------|
| 앱 형태 | 메뉴바 상주(LSUIElement), Dock 없음 | `App.swift` |
| 스크린샷 감지 | **이벤트 기반**(`DispatchSource`, 폴링 아님). 시스템 스크린샷 폴더 감시 | `FileWatcherService.swift:47` |
| 캡처 기능 | **없음** — 직접 캡처 안 함. macOS 기본 캡처(⌘⇧4 등)를 폴더 감시로 잡아챔 | — |
| 선반 저장 | **메모리 전용**, 최대 50개, 앱 종료 시 소멸 | `ScreenshotStore.swift:45,70` |
| 썸네일 | 생성함(300px). 단, 원본 `NSImage`도 함께 메모리 보유 | `ScreenshotStore.swift:20-24` |
| 밖으로 드래그 | SwiftUI `.onDrag`, 단일 항목만 | `QuickPanel.swift:568` |
| 파일 검색 | `mdfind -name` (Spotlight) | `SearchService.swift:90` |
| 로그인 시 실행 | `SMAppService` 구현됨 | `App.swift:87` |
| 단축키 | ⌥Q(패널 토글) **하나만** 실제 등록 | `App.swift:118` |
| 라이선스 | freemium 스캐폴딩(현재 전부 무료) | `LicenseService.swift` |
| 빌드 | `swiftc`, **arm64 전용**, 서명/공증 단계 없음 | `build.sh` |

**개발자가 이미 계획해둔 미구현 기능** (`LicenseService.swift:5-13` 주석):
`imageEditing`, `ocrExtraction`, `screenRecording`, `cloudSync` — 아래 로드맵과 일치.

---

## 1. 기능 고도화 (우선 트랙)

### 🥇 1-A. 선반 영속화 (Persistence)
- **현황**: `ScreenshotStore.items`가 `@Published` 배열뿐. 디스크 저장/로드 없음 → 재시작 시 전멸.
- **목표**: 앱을 껐다 켜도 선반 항목이 유지. "어제 캡처한 거" 다시 꺼내기.
- **구현**:
  - 메타데이터(`fileURL`, `date`, `isImageFile`)를 `Codable` 구조로 `~/Library/Application Support/Quick/shelf.json`에 저장.
  - 이미지 원본은 재저장하지 말고 `fileURL`만 기록 → 로드 시 파일에서 지연 로드. (파일이 삭제됐으면 항목 스킵)
  - `ScreenshotStore.init()`에서 load, `add/remove/clearAll`에서 debounce 저장.
- **난이도**: 낮음 · **임팩트**: 높음 (기본기)

### 🥈 1-B. OCR — 스크린샷에서 텍스트 추출
- **현황**: 없음. `Feature.ocrExtraction`으로 예약만 됨.
- **목표**: 항목 우클릭 → "텍스트 복사". 코드/에러메시지/문서 캡처 시 킬러 기능.
- **구현**: Apple **Vision** `VNRecognizeTextRequest` (온디바이스, 무료, 오프라인).
  - 한국어+영어: `recognitionLanguages = ["ko-KR","en-US"]`, `recognitionLevel = .accurate`.
  - 결과를 클립보드에 텍스트로. 추가 프레임워크 불필요.
- **난이도**: 낮음~중 · **임팩트**: 높음 (경쟁 앱 대비 차별화)

### 🥉 1-C. 마크업/주석 에디터
- **현황**: 없음. `Feature.imageEditing`으로 예약만 됨.
- **목표**: 캡처 직후/항목 더블클릭 → 자르기·화살표·사각형·텍스트·**민감정보 블러(redaction)**.
- **구현**: 별도 `NSWindow` + `Canvas`/`CALayer` 오버레이 편집기. 최소 버전은 자르기 + 블러 + 화살표부터.
  - 블러는 `CIGaussianBlur`/`CIPixellate`로 선택 영역 마스킹.
- **난이도**: 중~높음 (가장 큰 작업) · **임팩트**: 매우 높음 (Shottr/CleanShot 급 도약)
- **권장**: 1-A, 1-B 이후 착수. 별도 서브프로젝트로 분리.

### 보조 기능 (여력 시)
- **다중 선택 드래그(스택)**: 여러 항목을 한 번에 드래그. `QuickPanel.swift:568`의 `.onDrag`를 다중 `NSItemProvider`로 확장 + 선택 상태(`Set<UUID>`). — Dropover 시그니처 기능.
- **"링크로 복사"(업로드 공유)**: 이미지 호스팅/클라우드 업로드 후 URL 클립보드. `Feature.cloudSync`와 연결.
- **화면 녹화 → GIF**: `Feature.screenRecording`. 큰 작업, 후순위.

---

## 2. 기술 개선 (우선 트랙)

### 2-A. 메모리 최적화 — 원본 이미지 상시 보유 제거 ⭐
- **현황**: `ScreenshotItem`이 썸네일 + **원본 `NSImage`**를 둘 다 보유(`ScreenshotStore.swift:6,14`). 50개 × 레티나 원본 = RAM 폭식.
- **개선**: 원본은 드래그/복사 순간에만 `fileURL`에서 로드. 평상시엔 썸네일만.
  - 썸네일도 `QLThumbnailGenerator`(QuickLook)로 만들면 비이미지 파일도 일관된 미리보기.
- **난이도**: 낮음 · **임팩트**: 높음 (안정성)

### 2-B. 파일 감시 견고성
- **현황**: `DispatchSource`(단일 디렉토리 FD, `.write` 마스크)로 **이미 폴링 아님** ✅.
- **주의점**: 이 방식은 (1) 하위 폴더 미감지 (2) 폴더가 통째로 교체되면 FD 무효화 위험. 스크린샷 폴더 단일 감시라 대체로 OK.
- **개선(선택)**: 사용자가 저장 위치를 바꾸면 감시 재시작하도록 `com.apple.screencapture.plist` 변경도 감시. 우선순위 낮음.

### 2-C. 실제 캡처 기능 도입 (ScreenCaptureKit)
- **현황**: 앱이 캡처를 **안 함**. `AppSettings.swift:37-39`의 핫키 설정은 macOS 기본값을 흉내낸 **죽은 설정**(실제 등록 안 됨).
- **목표**: 앱 자체 단축키로 영역/창/전체 캡처 → 폴더 경유 없이 바로 선반에 + (있으면) 마크업으로.
- **구현**: **ScreenCaptureKit**(`SCScreenshotManager`, macOS 14+) 권장. 구식 `CGWindowListCreateImage`는 deprecation·권한 경고.
  - `LicenseService`의 `areaCapture/windowCapture/fullScreenCapture` Feature가 이걸 위한 자리.
  - 화면 녹화 권한(TCC) 온보딩 필요 (아래 3-C).
- **난이도**: 중 · **임팩트**: 높음 (수동 선반 → 능동 캡처 도구로 승격)

---

## 3. 배포 신뢰성 (지금은 후순위지만 배포 전 필수)

### 3-A. Developer ID 서명 + 공증(notarization)
- **현황**: `build.sh`에 서명 단계 자체가 없음. 현재 ad-hoc → 남의 맥에서 "확인되지 않은 개발자" 차단.
- **필요**: 유료 Apple Developer($99/년) → `codesign`(Developer ID) → `notarytool` 공증 → `stapler staple`.
- 이게 있어야 더블클릭으로 열림.

### 3-B. 유니버설 바이너리
- **현황**: `build.sh`가 `-target arm64-apple-macos13.0` **arm64 전용** → 인텔 맥 실행 불가.
- **개선**: `x86_64` 슬라이스도 빌드 후 `lipo -create`로 병합.

### 3-C. 화면 캡처 권한 온보딩
- **현황**: `Info.plist`에 `NSQuickUsageDescription`이라는 **잘못된 키** 존재(무효).
- 실제 캡처(2-C) 도입 시 화면 녹화 TCC 권한 필요 → 첫 실행 안내 화면 + `SCShareableContent` 권한 요청 흐름.

### 3-D. 자동 업데이트
- **현황**: 없음. 배포 후 버그 픽스 전달 수단 부재.
- **개선**: **Sparkle** 프레임워크(네이티브 표준) + appcast.xml.

---

## 4. 코드에서 발견한 문제 (Quick Wins)

| # | 문제 | 위치 | 조치 |
|---|------|------|------|
| 1 | 디버그 로그를 `/tmp/quick_debug.log`에 매 이벤트마다 기록 (성능·프라이버시: 스크린샷 파일명 유출) | `FileWatcherService.swift:4-16` | 릴리스 빌드에서 제거/비활성 |
| 2 | 새 스크린샷 감지 시 **무조건** 클립보드 덮어씀 — `AppSettings.copyToClipboard` 설정 무시 | `FileWatcherService.swift:117-119` | 설정 반영(`StorageService.copyToClipboard` 경유) |
| 3 | 스크린샷 판별이 파일명에 "스크린샷/screenshot/cleanshot" 포함 필수 — 로케일/커스텀 이름에 취약 | `FileWatcherService.swift:131-137` | 폴더 기준이므로 확장자만 체크로 완화 검토 |
| 4 | 설정 클래스 이중화(`AppSettings` + `QuickSettings`) — 중복/혼선 | `Models/` | 하나로 통합 |
| 5 | `StorageService.saveToFile`가 감시 경로에서 호출 안 됨 (죽은 코드 가능성) | `StorageService.swift:21` | 사용처 확인 후 정리 |
| 6 | 로케일 한국어(`ko`) 단일 | `Info.plist` | 해외 배포 시 영어 최소 지원 |

---

## 5. 권장 진행 순서

```
✅ 1) Quick Wins #1·#2       (완료 — 디버그로그 게이트, 클립보드 설정 반영)
✅ 2) 1-A 선반 영속화        (완료 — shelf.json, 통합테스트 통과)
✅ 3) 2-A 메모리 최적화      (완료 — 원본 미보유, fullImage 지연 로드)
✅ 4) 1-B OCR                (완료 — Vision, 한글+영문 검증)
✅ 5) 1-C 마크업 에디터 MVP  (완료 — 사각형/화살표/가리기/자르기, 엔진 헤드리스 검증)
── 다음 ──
   6) 2-C 캡처(ScreenCaptureKit) + 3-C 권한 온보딩
   7) 마크업 확장: 텍스트 도구, 실행취소 스택, 되돌리기(redo)
   8) 다중선택 드래그(스택)
── 배포 직전 ──
   9) 3-A 서명·공증 / 3-B 유니버설 / 3-D 자동업데이트
```

> 마크업 엔진 구현 중 **버그 하나 발견·수정**: 가리기(CIPixellate) 패치가 `cropping(to:)`의
> top-left 원점과 그리기의 bottom-left 원점 불일치로 **세로로 뒤집힌 위치**에 찍히던 문제 →
> 클리핑 방식으로 변경(`ImageMarkup.swift`). 비대칭 배치 테스트로 회귀 검증함.

> 참고: 위 항목 대부분은 `LicenseService`의 미구현 `Feature`와 매핑됨 →
> 유료화(Pro) 경계를 처음부터 이 enum으로 그으면 freemium 전환이 쉬움.
