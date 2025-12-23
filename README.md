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

## 최근 변경 사항 (2025-12-23)

### 1. Phantom 지갑 SIWS (Sign In With Solana) 자동 트리거
- **기능**: Phantom 지갑 연결 성공 직후, 자동으로 `signInWithSolana`를 호출하여 지갑 소유권을 암호학적으로 증명합니다.
- **UX 개선**: 연결 -> 앱 복귀 -> 서명 요청 -> 앱 복귀의 흐름을 자연스럽게 연결했습니다.
- **구현**: `WalletService`에 `signInWithSolana` 래퍼 추가 및 온보딩 로딩 화면에 진행률 UI 반영.

### 2. OKX 지갑 무한 로딩 해결 (Optimistic Session Check)
- **문제 해결**: OKX 지갑에서 승인 후 앱으로 복귀했을 때, WebSocket Relay 연결이 끊어져 무한 로딩에 빠지는 문제를 해결했습니다.
- **낙관적 세션 확인**: 앱이 `resumed` 상태가 될 때 Relay 연결 여부와 관계없이 로컬 세션 저장소를 즉시 조회하여 연결 성공을 감지합니다.
- **안정성**: 타임아웃 발생 시에도 마지막으로 한 번 더 세션을 확인하도록 개선했습니다.

### 3. 멀티 세션 관리 구조 도입 (Foundation)
- **MultiSessionState**: 여러 지갑(WalletConnect 및 Phantom)의 세션을 동시에 관리하기 위한 상태 모델을 도입했습니다.
- **PersistedSession**: 세션 데이터를 로컬에 영구 저장하고 복원하는 구조를 개선하고 있습니다.
- **목표**: 사용자가 여러 지갑을 연결해두고 자유롭게 전환하며 사용할 수 있는 환경 제공.

### 4. Sentry 기반 로깅 및 연결 복구 UX
- **Sentry 도입**: `SentryService`를 통해 지갑 연결 실패 및 예외 상황을 체계적으로 추적합니다.
- **복구 옵션**: 연결 승인이 지연되거나 실패할 경우, 사용자에게 재시도, QR 코드 복사 등의 복구 옵션을 제공하는 UI를 추가했습니다.
- **Debug 로그**: 연결 단계별 상세 로그를 통해 디버깅 효율을 높였습니다.

### 5. 기타 안정성 개선
- **WalletConnect Relay Watchdog**: 백그라운드에서 복귀 시 끊어진 Relay 연결을 감지하고 자동으로 재연결합니다.
- **좀비 세션 방지**: 연결 시도 전 이전의 유효하지 않은 세션 데이터를 정리하여 충돌을 방지합니다.
- **코인베이스 네이티브 SDK**: Android/iOS 네이티브 SDK를 통합하여 UX를 개선했습니다.

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
- [Phantom Deep Links](https://docs.phantom.app/solana/integrating-phantom/deep-linking)