# TODO — Mac App Store 제출

코드 측 준비는 `mas-prep` 브랜치에서 끝났다 (상세: [docs/mac-app-store.md](docs/mac-app-store.md)).
아래는 전부 **Apple Developer 계정 보유자만 할 수 있는 작업**과 그 이후의 제출 절차다.
위에서 아래 순서대로 진행하면 된다.

## 1. 인증서 발급 (developer.apple.com 또는 Xcode)

기존 Developer ID 인증서는 MAS에 재사용 불가. 두 개 새로 필요하다.

- [ ] `Apple Distribution` 인증서 — .app 서명용
- [ ] `Mac Installer Distribution` 인증서 — .pkg 서명용
  - Xcode → Settings → Accounts → Manage Certificates → `+` 가 가장 빠름
  - 발급 후 `security find-identity -v -p codesigning | grep -E "Apple Distribution|Installer"` 로 키체인 확인

## 2. App ID 등록 (developer.apple.com → Identifiers)

- [ ] `as.kargn.cctrans` (explicit) — App Sandbox capability 체크
- [ ] `as.kargn.cctrans.tauri-helper` (explicit) — App Sandbox capability 체크
  - 번들에 내장된 Tauri helper는 NSWorkspace로 별도 실행되는 독립 앱이라 자체 App ID가 필요하다

## 3. 프로비저닝 프로파일 (developer.apple.com → Profiles)

- [ ] 타입 **Mac App Store**, App ID `as.kargn.cctrans`, 인증서 = 위의 Apple Distribution → 다운로드
- [ ] 같은 방식으로 `as.kargn.cctrans.tauri-helper`용도 생성 → 다운로드
  - 메인 프로파일은 `build-mas.zsh`가 `Contents/embedded.provisionprofile`로 임베드한다.
    helper 프로파일 임베드는 스크립트에 아직 없음 → 첫 ingest에서 거부되면
    `TAURI_HELPER_DEST/Contents/embedded.provisionprofile` 복사 단계를 build-mas.zsh에 추가할 것

## 4. App Store Connect 앱 레코드

- [ ] appstoreconnect.apple.com → My Apps → `+` → New App (macOS)
- [ ] 이름 "CCTrans" 스토어 전역 유니크 확인 (선점됐으면 대안: "CCTrans Translator" 등)
- [ ] Bundle ID `as.kargn.cctrans` 연결, SKU 임의 지정
- [ ] **개인정보 정책 URL 필수** — kargn.as 아래에 페이지 하나 만들어야 함
- [ ] Privacy nutrition label 입력
  - OpenRouter 키는 로컬 보관, 번역 텍스트는 사용자가 선택한 경우에만 OpenRouter로 전송됨
  - Apple Translation은 온디바이스 — 개발자 수집 데이터 없음으로 신고 가능
- [ ] 카테고리 Productivity, 가격 무료(또는 결정), 수출 규정 = 표준 HTTPS만 사용 → exempt

## 5. 제출용 빌드 생성

```sh
CCTRANS_VERSION=<버전> \
CCTRANS_MAS_SIGN_IDENTITY="Apple Distribution: Sangrak Choi (<TEAM_ID>)" \
CCTRANS_TEAM_ID=<TEAM_ID> \
CCTRANS_MAS_PROFILE=<다운로드한 메인 프로파일 경로> \
CCTRANS_MAS_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Sangrak Choi (<TEAM_ID>)" \
./scripts/build-mas.zsh
```

- [ ] `dist-mas/CCTrans-mas-<버전>.pkg` 생성 확인
- [ ] `codesign -dvv --entitlements - dist-mas/CCTrans.app` — sandbox=true + application-identifier 확인
- [ ] 버전은 직배포 릴리즈와 무관하게 ASC 기준 단조 증가만 지키면 됨

## 6. 업로드

- [ ] Transporter.app (Mac App Store에서 설치) 으로 .pkg 업로드
  - CI 자동화가 필요해지면: `xcrun altool --upload-package` + App Store Connect API 키
- [ ] ASC → TestFlight 탭에서 빌드 처리 완료 대기 (자동 ingest 검사에서 entitlements 문제가 여기서 걸러짐)

## 7. TestFlight QA (제출 전 실기기 확인)

- [ ] 첫 실행: 로컬 모델 설정창이 **안** 뜨고 provider가 Apple Translation인지
- [ ] Cmd+C 더블 → Input Monitoring 권한 안내 → 허용 후 재실행 → 번역 토스트
- [ ] 권한 거부 상태에서도 같은 텍스트 2회 복사(pasteboard 폴백)로 번역되는지
- [ ] 미설치 언어쌍 → Apple 언어팩 다운로드 다이얼로그 플로우
- [ ] 스크린샷 번역 (Shift+Cmd+2) → Screen Recording 권한 플로우
- [ ] 토스트가 caret이 아니라 toastPosition 설정 위치에 뜨는지
- [ ] 설정 UI: provider 2개만 노출(Apple/OpenRouter), Permission Helper에 Accessibility 항목 없음
- [ ] 메뉴바에 "Check for Updates..." 없음 (Sparkle 미포함)
- [ ] GitHub star 프롬프트 안 뜸 (MAS 채널 자동 비활성)

## 8. 심사 제출

- [ ] 스크린샷: 1280×800 / 1440×900 / 2560×1600 / 2880×1800 중 한 규격으로 통일
- [ ] **Review note 필수 작성** (없으면 거절 확률 높음):
  - 메뉴바 전용(LSUIElement) 앱 — Dock에 안 보이며 메뉴바 아이콘에서 시작한다는 안내
  - 사용법: 아무 앱에서 같은 텍스트를 2번 복사하면 번역 토스트가 뜬다
  - Input Monitoring/Screen Recording 권한이 각각 왜 필요한지 한 줄씩
  - 리뷰어용 OpenRouter 데모 API 키 (Apple Translation은 키 없이 동작하므로 핵심 기능 시연은 키 없이도 가능하다고 명시)
- [ ] 제출 → 심사 중 거절 사유는 docs/mac-app-store.md §6 리스크 표 참조

## 9. 남은 결정 (제출 전 아무 때나)

- [ ] 무료 확정? (현재 계획은 무료 기준)
- [ ] `mas-prep` 브랜치 main 머지 시점 — 머지하면 직배포 자동 릴리즈에도 CGEventTap/Apple Translation이 포함됨
