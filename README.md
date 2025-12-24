# wallet_integration_practice

iLity Hub를 위한 지갑 연동 실습

## 기능

- **멀티체인 지갑 지원**: EVM 체인 (Ethereum, Polygon 등) + Solana
- **WalletConnect v2 연동**: Reown AppKit 및 커스텀 어댑터 사용
- **딥링크 지갑 연결 흐름**: 앱 간 전환 및 세션 관리
- **다중 세션 관리 (WIP)**: 여러 지갑의 연결 상태 유지 및 전환 (기초 구현)
- **지원되는 지갑**:
  - 메타마스크 (MetaMask)
  - OKX 월렛 (OKX Wallet)
  - 트러스트 월렛 (Trust Wallet)
  - 팬텀 (Phantom)
  - 래비 (Rabby)
  - 코인베이스 (Coinbase Smart Wallet)

## 최근 변경 사항

### 2025-12-24: Phantom 지갑 레거시 세션 마이그레이션 및 복원 강화

**기능**: 기존 단일 세션 저장소에 저장된 Phantom 지갑 데이터를 새로운 Multi-Session 아키텍처로 안전하게 이관하고, 앱 재시작 시 복원 안정성을 강화했습니다.

**주요 개선 사항**:
1.  **레거시 세션 마이그레이션**:
    *   `MultiSessionDataSource`에 마이그레이션 로직 추가: 앱 초기화 시 기존 `phantom_session_v1` 키에 저장된 세션이 있으면 Multi-Session 저장소로 자동 이관.
    *   기존 사용자들의 로그인 상태 유지 보장.
2.  **Phantom 어댑터 복원 로직 개선**:
    *   `PhantomAdapter`가 초기화 시점에 `localDataSource`가 주입되지 않았더라도, 이후 `restoreSession()` 호출 시 지연된 복원을 시도하도록 수정.
    *   `WalletNotifier`에서 Multi-Session 저장소에 데이터가 없더라도, 레거시 저장소를 확인하여 Phantom 세션을 복구하는 2차 방어선(Fallback) 구축.
3.  **데이터 동기화**:
    *   Phantom 연결/복원 성공 시 레거시 저장소와 Multi-Session 저장소 양쪽에 데이터를 동기화하여 호환성 확보.

**변경된 파일**:
- `lib/data/datasources/local/multi_session_datasource.dart`: 마이그레이션 로직 구현
- `lib/presentation/providers/wallet_provider.dart`: 복원 및 마이그레이션 오케스트레이션
- `lib/wallet/adapters/phantom_adapter.dart`: 지연된 복원(Late Restoration) 지원 및 세션 관리 강화

---

### 2025-12-24: 세션 복원 UX 개선 (Skeleton UI & Splash)

**기능**: 앱 Cold Start 시 저장된 세션 복원 과정을 시각적으로 표시하여 사용자 경험을 크게 개선했습니다.

**주요 개선 사항**:
1.  **Session Restoration Provider**:
    *   `SessionRestorationState` 및 `SessionRestorationNotifier`를 통해 복원 상태(checking, restoring, completed, failed) 추적.
    *   복원 진행률, 현재 복원 중인 지갑 이름, 타임아웃 관리 지원.
2.  **Session Restoration Splash**:
    *   전체 화면 스플래시로 복원 진행 상태 표시.
    *   펄스 로고 애니메이션, 진행률 바(determinate/indeterminate), 상태 텍스트.
    *   10초 이상 소요 시 "건너뛰기" 버튼 표시.
3.  **Skeleton UI 위젯**:
    *   `WalletCardSkeleton`: WalletCard의 스켈레톤 버전으로 로딩 중 표시.
    *   `ConnectedWalletsSkeleton`: ConnectedWalletsSection의 스켈레톤 버전.
4.  **Shimmer 위젯 라이브러리**:
    *   `ShimmerBox`, `ShimmerText`, `ShimmerAvatar`, `ShimmerCard`, `ShimmerIcon` 등 재사용 가능한 shimmer 효과 위젯.
5.  **부드러운 전환 애니메이션**:
    *   `AnimatedSwitcher`를 사용하여 스플래시→홈 화면, 스켈레톤→실제 컨텐츠 전환을 부드럽게 처리.
    *   fade + slide 조합으로 자연스러운 전환 효과.

**변경된 파일**:
- `lib/main.dart` - 세션 복원 상태 기반 화면 라우팅 로직
- `lib/presentation/providers/wallet_provider.dart` - 복원 진행률 업데이트
- `lib/presentation/providers/session_restoration_provider.dart` (신규) - 복원 상태 관리
- `lib/presentation/screens/home/home_screen.dart` - 스켈레톤 UI 적용
- `lib/presentation/widgets/splash/session_restoration_splash.dart` (신규)
- `lib/presentation/widgets/common/shimmer.dart` (신규)
- `lib/presentation/widgets/wallet/wallet_card_skeleton.dart` (신규)
- `lib/presentation/widgets/wallet/connected_wallets_skeleton.dart` (신규)
- `lib/presentation/presentation.dart` - 배럴 export 추가

---

### 2025-12-23: Phantom 지갑 SIWS (Sign In With Solana) 자동 트리거 구현

- **기능**: Phantom 지갑 연결 성공 직후, 자동으로 `signInWithSolana`를 호출하여 지갑 소유권을 암호학적으로 증명합니다.
- **UX 개선**: 연결 -> 앱 복귀 -> 서명 요청 -> 앱 복귀의 흐름을 자연스럽게 연결했습니다.
- **구현**: `WalletService`에 `signInWithSolana` 래퍼 추가 및 온보딩 로딩 화면에 진행률 UI 반영.

### 2025-12-23: OKX 지갑 무한 로딩 해결 (Optimistic Session Check)

- **문제 해결**: OKX 지갑에서 승인 후 앱으로 복귀했을 때, WebSocket Relay 연결이 끊어져 무한 로딩에 빠지는 문제를 해결했습니다.
- **낙관적 세션 확인**: 앱이 `resumed` 상태가 될 때 Relay 연결 여부와 관계없이 로컬 세션 저장소를 즉시 조회하여 연결 성공을 감지합니다.
- **안정성**: 타임아웃 발생 시에도 마지막으로 한 번 더 세션을 확인하도록 개선했습니다.

### 2025-12-23: 멀티 세션 관리 구조 도입 (Foundation)

- **MultiSessionState**: 여러 지갑(WalletConnect 및 Phantom)의 세션을 동시에 관리하기 위한 상태 모델을 도입했습니다.
- **PersistedSession**: 세션 데이터를 로컬에 영구 저장하고 복원하는 구조를 개선하고 있습니다.
- **목표**: 사용자가 여러 지갑을 연결해두고 자유롭게 전환하며 사용할 수 있는 환경 제공.

### 2025-12-23: Sentry 기반 로깅 및 연결 복구 UX

- **Sentry 도입**: `SentryService`를 통해 지갑 연결 실패 및 예외 상황을 체계적으로 추적합니다.
- **복구 옵션**: 연결 승인이 지연되거나 실패할 경우, 사용자에게 재시도, QR 코드 복사 등의 복구 옵션을 제공하는 UI를 추가했습니다.
- **Debug 로그**: 연결 단계별 상세 로그를 통해 디버깅 효율을 높였습니다.

### 2025-12-23: 기타 안정성 개선

- **WalletConnect Relay Watchdog**: 백그라운드에서 복귀 시 끊어진 Relay 연결을 감지하고 자동으로 재연결합니다.
- **좀비 세션 방지**: 연결 시도 전 이전의 유효하지 않은 세션 데이터를 정리하여 충돌을 방지합니다.
- **코인베이스 네이티브 SDK**: Android/iOS 네이티브 SDK를 통합하여 UX를 개선했습니다.

---

### 2025-12-19: Sentry 기반 로깅 및 지갑 연결 복구 UX 강화

**기능**: Sentry 에러 추적 도입과 지갑 연결 상태 로깅 체계화, 승인 지연 시 복구 옵션 제공, OKX 지갑 지원 정리.

**주요 개선 사항**:
1.  **Sentry 도입**:
    *   `SentryService` 추가 및 `sentry_flutter` 의존성 반영.
    *   Debug 모드에서 `DebugLogService`로 Sentry 이벤트를 메모리에 저장해 실시간 확인 가능.
2.  **지갑 연결 로깅 체계화**:
    *   `WalletLogService` + 전용 모델/enum으로 연결 단계, 릴레이/세션 상태, 딥링크 리턴을 구조화 기록.
    *   딥링크 핸들러 예외를 안전 처리하고 경고 수준으로 기록.
3.  **승인 지연 복구 UX**:
    *   승인 대기 15초 경과 시 QR 코드/URI 복사/재시도 옵션을 안내.
    *   앱 복귀 시 릴레이 재연결 로직 강화 및 백그라운드 재시도 제한.
4.  **지갑 지원 정리**:
    *   OKX 관련 어댑터/상수/플랫폼 스킴 제거 및 목록 정리.

**변경된 파일**:
- `lib/core/services/sentry_service.dart` (신규)
- `lib/core/services/debug_log_service.dart` (신규)
- `lib/core/services/wallet_log_service.dart` (신규)
- `lib/core/models/wallet_log_*.dart` (신규)
- `lib/wallet/adapters/walletconnect_adapter.dart`
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `pubspec.yaml`

---

### 2025-12-17: 포괄적인 WalletConnect 안정성 및 UX 개선

**기능**: WalletConnect 기반 지갑(메타마스크, 트러스트 월렛)의 주요 안정성 개선 및 팬텀 월렛의 UX 수정.

**주요 개선 사항**:
1.  **WalletConnect 안정성**:
    *   **릴레이(Relay) 재연결**: 앱이 백그라운드에서 다시 활성화될 때 끊어진 WebSocket 릴레이 연결을 감지하고 다시 연결하는 강력한 "Watchdog" 로직 추가.
    *   **릴레이 상태 일관성**: `_onRelayError`에서 릴레이를 즉시 연결 끊김으로 표시하여, 앱이 잘못된 연결 상태로 인식하고 재연결에 실패하는 "좀비 상태"를 방지하는 중요한 수정 적용.
    *   **세션 감지**: 앱이 백그라운드에 있는 동안 초기 이벤트를 놓치더라도 세션 승인을 캡처할 수 있도록 이중 확인 시스템(이벤트 리스너 + 폴링) 구현.
    *   **충돌 해결**: 새로운 연결을 시작하기 전에 오래된 페어링을 지우는 `clearPreviousSessions()`를 추가하여 지갑 간 충돌 방지 (예: 트러스트 월렛이 팬텀 링크를 여는 문제).

2.  **지갑별 업데이트**:
    *   **메타마스크(MetaMask)**: 연결 흐름을 `prepareConnection` 패턴으로 리팩토링. 이제 앱을 열기 *전*에 URI를 생성하여 유효한 딥링크가 준비되도록 보장.
    *   **트러스트 월렛(Trust Wallet)**:
        *   안정적인 딥링크를 위해 `prepareConnection` 패턴 채택.
        *   "유령" 리다이렉트를 방지하기 위해 이전 세션 자동 삭제 기능 추가.
        *   URI 생성 신뢰성 향상.
    *   **팬텀 월렛(Phantom Wallet)**:
        *   `disconnect` 동작을 수정하여 연결 해제 URL을 실행하는 대신 로컬 상태만 지우도록 변경. 이로써 연결 해제 시 `phantom.com`으로 리다이렉트되는 번거로운 브라우저 이동을 방지.

**변경된 파일**:
- `lib/wallet/adapters/walletconnect_adapter.dart`: 핵심 안정성 로직 (Watchdog, 릴레이 재연결).
- `lib/wallet/adapters/metamask_adapter.dart`: `prepareConnection`을 사용하도록 리팩토링.
- `lib/wallet/adapters/trust_wallet_adapter.dart`: `prepareConnection` 및 세션 삭제를 사용하도록 리팩토링.
- `lib/wallet/adapters/phantom_adapter.dart`: 연결 해제 로직 개선.

---

### 2025-12-16: 래비(Rabby) 월렛 UX 및 dApp URL 설정

**기능**: 래비 월렛 연결 흐름 개선 및 dApp URL 설정 업데이트.

**변경 사항**:
- **래비 월렛**: 래비 월렛은 표준 딥링크 대신 수동 dApp 브라우저 연결 흐름이 필요하므로 전용 가이드 다이얼로그를 다시 활성화.
- **UI 텍스트**: 래비 월렛 가이드 텍스트를 "브라우저(Browser)" 대신 "Dapps" 탭을 참조하도록 수정.
- **설정**: 더 나은 통합 테스트를 위해 `dappUrl`이 활성 개발 환경을 가리키도록 업데이트.

**변경된 파일**:
- `lib/core/constants/app_constants.dart`
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart`
- `lib/presentation/screens/onboarding/rabby_guide_dialog.dart`

---

### 2025-12-16: 트러스트 월렛 연결 UX 개선

**문제**: 트러스트 월렛 연결 시 최종적으로 연결 성공하지만, 중간에 "연결 실패" 메시지가 일시적으로 표시되는 문제.

**원인**: `_restoreAndCheckSession()` 메서드에서 relay 재연결 후 세션이 즉시 발견되지 않으면 에러 UI를 바로 표시. Trust Wallet은 세션 동기화가 느려서 500ms 대기 후에도 세션이 준비되지 않을 수 있지만, retry 로직이 작동하면 결국 연결됨.

**해결**:
1. `_restoreAndCheckSession()`에서 즉시 에러 UI 표시 대신 "서명 검증 중" 상태 유지
2. `clearPendingConnection()` 조기 호출 제거 → retry 로직이 계속 작동
3. 기존 스트림 리스너가 최종 연결 성공/실패 처리하도록 위임

**기대 동작**:
- 연결 중: "서명 검증 중" 상태 유지
- 연결 성공: 메인 화면으로 이동
- 진짜 연결 실패: timeout 후 에러 표시

**변경된 파일**:
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart` - 성급한 에러 UI 표시 제거

---


### 2025-12-12: 코인베이스(Coinbase) 월렛 네이티브 SDK 및 Reown AppKit 통합

**기능**: 코인베이스 월렛 통합을 네이티브 SDK 사용으로 마이그레이션하고 통합된 WalletConnect 처리를 위해 Reown AppKit 도입.

**변경 사항**:
- **코인베이스 월렛**: Android/iOS에서 더 나은 네이티브 경험을 위해 일반 WalletConnect에서 `coinbase_wallet_sdk`로 전환.
- **Reown AppKit**: 더 나은 신뢰성과 기능 세트를 위해 커스텀 구현을 대체하여 WalletConnect 세션을 관리하는 `ReownAppKitService` 추가.
- **설정**: 코인베이스 월렛에 필요한 패키지 가시성 쿼리 및 딥링크 스킴으로 `AndroidManifest.xml` 업데이트.

**변경된 파일**:
- `lib/wallet/adapters/coinbase_wallet_adapter.dart`
- `lib/wallet/services/reown_appkit_service.dart` (신규)
- `android/app/src/main/AndroidManifest.xml`
- `pubspec.yaml`

### 2025-12-10: 지갑 복귀 시 무한 로딩 수정

**문제**: 지갑에서 연결 승인 후 앱으로 돌아오면 온보딩 화면에서 무한 로딩이 표시됨.

**원인**:
- 앱이 백그라운드에 있는 동안 WalletConnect 세션 이벤트가 발생함
- 앱이 재개되었을 때 스트림 구독은 이미 연결 이벤트를 놓친 상태임
- UI는 오지 않을 스트림 이벤트를 무기한 기다림

**해결**:
1. 동기 상태 확인을 위해 `WalletService`에 `currentConnectionStatus` 게터 추가
2. 스트림을 구독하기 **전**에 현재 연결 상태를 확인하도록 `OnboardingLoadingPage` 수정
3. 콜드 스타트 복구 시나리오를 위해 `_restoreAndCheckSession()` 추가

**변경된 파일**:
- `lib/wallet/services/wallet_service.dart` - `currentConnectionStatus` 게터 추가
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart` - 즉시 상태 확인 + 복원 로직

## 시작하기

### 전제 조건
- Flutter 3.x
- Dart 3.x

### 설치

```bash
# 의존성 가져오기
flutter pub get

# 코드 생성 실행 (JSON Serialization 등)
dart run build_runner build --delete-conflicting-outputs

# 앱 실행
flutter run
```

### 빌드

```bash
# 디버그 APK
flutter build apk --debug

# 릴리스 APK
flutter build apk --release
```

## 아키텍처

Clean Architecture 원칙을 따르며 다음 계층으로 구성됩니다:

```
lib/
├── core/          # 공유 유틸리티, 상수, 에러, 서비스 (Log, Sentry, DeepLink)
├── data/          # 데이터 계층 (모델, 데이터소스, Repository 구현)
├── domain/        # 비즈니스 로직 (엔티티, Repository 인터페이스, UseCases)
├── wallet/        # 지갑 연동 계층 (어댑터 패턴, WalletConnect/Phantom 서비스)
└── presentation/  # UI 계층 (화면, 위젯, Provider 상태 관리)
```

## 참고 자료

- [Flutter 문서](https://docs.flutter.dev/)
- [WalletConnect v2 문서](https://docs.walletconnect.com/)
- [Reown AppKit](https://docs.reown.com/)
- [Phantom Deep Links](https://docs.phantom.app/solana/deep-links)
