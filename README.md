# Flutter Wallet Integration Module

Flutter 기반 멀티체인 지갑 연동 모듈

## 기능

- **멀티체인 지갑 지원**: EVM 체인 (Ethereum, Polygon, Arbitrum, Optimism, Base, BNB) + Solana
- **WalletConnect v2 연동**: Reown AppKit 및 커스텀 어댑터 패턴 사용
- **딥링크 지갑 연결 흐름**: 앱 간 전환 및 세션 관리
- **다중 세션 관리**: 여러 지갑의 연결 상태 유지 및 전환

### 지원 지갑

| 지갑 | EVM | Solana | 연결 방식 |
|------|-----|--------|-----------|
| MetaMask | ✓ | - | WalletConnect + Deep Link |
| WalletConnect | ✓ | - | WalletConnect Protocol |
| Coinbase | ✓ | ✓ | Native SDK |
| OKX Wallet | ✓ | ✓ | WalletConnect + Deep Link |
| Trust Wallet | ✓ | ✓ | WalletConnect |
| Rainbow | ✓ | - | WalletConnect |
| Phantom | ✓ | ✓ | Native SDK (Solana) |
| Rabby | ✓ | - | WalletConnect |

## 시작하기

### 전제 조건
- Flutter 3.x
- Dart 3.x

### 설치

```bash
# 의존성 가져오기
flutter pub get

# 코드 생성 실행 (freezed, json_serializable, riverpod_generator)
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
├── core/              # 공유 유틸리티, 상수, 에러, 서비스
│   ├── constants/     # 앱, 체인, 지갑 상수
│   ├── errors/        # 타입화된 Failure 및 Exception
│   ├── services/      # DeepLink, Connectivity, Logging 서비스
│   ├── utils/         # 주소 검증, 암호화, 백오프 유틸리티
│   └── models/        # 로그 열거형 및 모델
├── data/              # 데이터 계층
│   ├── datasources/   # Local (캐시, 세션) & Remote (RPC)
│   ├── models/        # 영속화된 세션 모델
│   └── repositories/  # Repository 구현체
├── domain/            # 비즈니스 로직
│   ├── entities/      # 핵심 엔티티 (Wallet, Session, Balance)
│   ├── repositories/  # Repository 인터페이스
│   └── usecases/      # 비즈니스 유스케이스
├── wallet/            # 지갑 연동 계층
│   ├── adapters/      # 지갑별 어댑터
│   ├── services/      # WalletService, SessionRegistry, Factory
│   ├── models/        # 어댑터 설정, 세션 결과
│   └── utils/         # Topic 검증 유틸리티
└── presentation/      # UI 계층
    ├── providers/     # Riverpod 상태 관리
    ├── screens/       # 화면 위젯
    └── widgets/       # 재사용 가능 UI 컴포넌트
```

### 지갑 어댑터 패턴

지갑 연동은 공통 인터페이스를 가진 어댑터 패턴을 사용합니다:

**기본 클래스:**
- `BaseWalletAdapter` - 공통 지갑 작업을 정의하는 추상 기본 클래스
- `EvmWalletAdapter` - EVM 특화 작업 확장 인터페이스 (switchChain, signTypedData)
- `SolanaWalletAdapter` - Solana 작업 확장 인터페이스 (signSolanaTransaction)

**구체적 어댑터:**
- `WalletConnectAdapter` - 일반 WalletConnect v2 구현
- `MetaMaskAdapter` - 딥링크 핸들링을 포함한 MetaMask 전용
- `PhantomAdapter` - Solana용 Phantom 네이티브 SDK
- `CoinbaseWalletAdapter` - Coinbase 네이티브 SDK
- `OKXWalletAdapter` - 적극적 재연결 설정을 가진 OKX
- `TrustWalletAdapter` - WalletConnect를 통한 Trust Wallet
- `RabbyWalletAdapter` - WalletConnect를 통한 Rabby
- `GenericWalletConnectAdapter` - 기타 WalletConnect 지갑용 폴백

**핵심 서비스:**
- `WalletService` - 어댑터 생명주기 관리, 활성 어댑터로 작업 라우팅
- `WalletAdapterFactory` - WalletType 기반 적절한 어댑터 생성
- `WalletConnectSessionRegistry` - 검증을 포함한 다중 세션 상태 관리

### 상태 관리

`presentation/providers/`에 정의된 Riverpod 사용:

**핵심 Provider:**
- `walletServiceProvider` - 싱글톤 WalletService 인스턴스
- `walletNotifierProvider` - 단일 지갑 작업용 StateNotifier
- `multiWalletNotifierProvider` - 다중 지갑 상태 관리

**연결 Provider:**
- `walletConnectionStreamProvider` - 연결 상태 업데이트 스트림
- `connectedWalletProvider` - 현재 연결된 지갑 엔티티
- `connectedWalletsProvider` - 모든 연결된 지갑 목록

**세션 Provider:**
- `sessionAccountsProvider` - 다중 계정 세션 지원
- `activeAccountNotifierProvider` - 활성 계정 선택
- `sessionRestorationProvider` - 앱 실행 시 세션 복원

### 핵심 엔티티

- `WalletEntity` - 연결된 지갑 상태 (address, type, chainId/cluster, sessionTopic)
- `WalletConnectionStatus` - 재시도 정보와 진행 메시지를 포함한 연결 상태
- `ChainInfo` - 블록체인 네트워크 설정 (chainId, cluster, rpcUrl)
- `WalletType` enum - 딥링크 스킴과 기능을 가진 지원 지갑 유형
- `PersistedSession` / `ManagedSession` - 세션 영속화 및 검증
- `SessionAccount` - 세션 내 개별 계정 (다중 계정 지원)

### 에러 처리

`core/errors/failures.dart`의 타입화된 Failure:

| Failure 유형 | 설명 |
|--------------|------|
| `WalletConnectionFailure` | 연결 문제 (timeout, rejected, notInstalled, sessionExpired) |
| `SignatureFailure` | 트랜잭션 서명 에러 (rejected, timeout, invalidParams) |
| `ChainFailure` | 체인 전환 문제 (unsupportedChain, switchFailed) |
| `NetworkFailure` | 네트워크 연결 문제 (noConnection, serverError, timeout) |
| `StorageFailure` | 로컬 스토리지 에러 (readFailed, writeFailed) |
| `BalanceFailure` | 잔액 조회 에러 (rpcError, invalidAddress, addressChainMismatch) |

### 세션 관리

**다중 세션 아키텍처:**
- `WalletConnectSessionRegistry` - 모든 WalletConnect 세션의 중앙 레지스트리
- `MultiSessionDataSource` - 다중 지갑 세션의 영속 저장소
- `ManagedSession` - 상태 추적을 포함한 세션 (active, inactive, stale, expired)
- 앱 재개 시 만료된 세션 자동 정리와 함께 세션 검증

**세션 상태:**
```dart
enum SessionState { active, inactive, stale, expired }
```

### 연결 및 복구

- `ConnectivityService` - 네트워크 상태 모니터링 (online, offline, unknown)
- `ExponentialBackoff` - 설정 가능한 백오프를 가진 재시도 로직
- `WalletReconnectionConfig` - 지갑별 재연결 전략 (aggressive, medium, lenient, standard)
- `RelayConnectionState` - WalletConnect 릴레이 연결 상태 추적

### 딥링크 흐름

`DeepLinkService` (싱글톤)이 지갑 콜백을 처리합니다. `WalletNotifier`에 등록된 핸들러가 host/path 기반으로 URI를 적절한 어댑터로 라우팅합니다.

**딥링크 스킴:**
- MetaMask: `metamask://`
- Coinbase: `cbwallet://`
- OKX Wallet: `okxwallet://`
- Trust Wallet: `trust://`
- Phantom: `phantom://`
- Rabby: `rabby://`
- Rainbow: `rainbow://`

## 멀티체인 지원

**EVM 체인** (`chainId: int` 사용):
- Ethereum (1), Sepolia (11155111)
- Polygon (137), Amoy (80002)
- BNB Chain (56, 97)
- Arbitrum One (42161), Sepolia (421614)
- Optimism (10), Sepolia (11155420)
- Base (8453), Sepolia (84532)

**Solana** (`cluster: String` 사용):
- mainnet-beta, devnet, testnet

`ChainType` 열거형이 체인 패밀리를 구분합니다 (evm, solana, sui).

## 유틸리티 서비스

- `AddressValidationService` - EVM/Solana 주소 포맷 검증
- `CryptoIsolate` - 성능을 위한 Isolate에서의 암호화 작업
- `TopicValidator` - WalletConnect topic 검증
- `WalletLogService` / `DebugLogService` - 컨텍스트를 포함한 구조화된 로깅
- `SentryService` - 예상 실패 필터링을 포함한 에러 리포팅
- `PendingConnectionService` - 대기 중인 지갑 연결 추적

## 최근 변경 사항

### 2026-01-05: 코드 정리 및 아키텍처 단순화 (Part 4)

**기능**: 사용하지 않는 레거시 코드, 위젯, 서비스를 제거하고 핵심 로직을 최적화하여 유지보수성을 향상시켰습니다.

**주요 개선 사항**:
1.  **레거시 코드 제거**:
    *   더 이상 사용되지 않는 `ReownAppKitService`를 완전히 제거하고, 관련 로직을 `WalletConnectAdapter` 및 `WalletConnectSessionRegistry`로 통합했습니다.
    *   초기 개발 단계에서 사용되던 `DebugLogProvider`(현재 `FileLogService`로 대체됨), `AccountSelectorDialog`, `WalletStatusIndicator` 등 불필요한 UI/Provider 컴포넌트를 삭제했습니다.
2.  **코드 최적화**:
    *   `WalletService` 및 `WalletProvider`에서 삭제된 컴포넌트와 관련된 의존성 및 죽은 코드(Dead Code)를 정리했습니다.
    *   주요 어댑터(`OKXWalletAdapter`, `WalletConnectAdapter`)의 코드를 정리하고 가독성을 개선했습니다.

---

### 2026-01-05: File-based Logging System & Session Debugging (Part 3)

**기능**: 세션 복원 및 콜드 스타트 이슈를 추적하기 위한 영구 파일 로깅 시스템 및 인앱 디버그 뷰어 도입.

**주요 개선 사항**:
1.  **File Log Service**:
    *   앱 재시작 간에도 유지되는 파일 기반 로깅 시스템 구현 (`FileLogService`).
    *   로그 로테이션(1MB 제한) 및 카테고리별 태깅(RESTORE, SDK, RELAY 등) 지원.
2.  **In-App Debug Viewer**:
    *   **DebugLogScreen**: 수집된 로그를 앱 내에서 실시간으로 확인하고 필터링할 수 있는 화면 추가.
    *   **기능**: 로그 새로고침, 자동 스크롤, 클립보드 복사, 공유(`share_plus`), 로그 초기화 기능 제공.
3.  **심층 세션 추적**:
    *   **MultiSessionDataSource**: 세션 로드 및 삭제 과정에 상세 로깅 적용.
    *   **WalletProvider**: 세션 복원 시도, 오판(Orphan) 감지, 재시도 로직 추적.

---

### 2026-01-05: WalletConnect Relay State Machine 및 Crypto Isolate 최적화 (Part 2)

**기능**: WalletConnect Relay 연결 상태를 스레드 안전하게 관리하는 State Machine 도입 및 암호화 연산의 Isolate 최적화.

**주요 개선 사항**:
1.  **Relay Connection State Machine**:
    *   **경쟁 상태(Race Condition) 방지**: `RelayConnectionStateMachine`을 도입하여 연결/재연결/해제 간의 상태 전이를 스레드 안전하게 관리합니다.
2.  **Crypto Isolate 최적화**:
    *   **백그라운드 연산**: Phantom 지갑의 페이로드 복호화, Base58 배치 디코딩, Ed25519 서명 검증 등 무거운 암호화 작업을 백그라운드 `Isolate`로 이관했습니다.
3.  **Address Validation (심층 방어)**:
    *   **RPC 호출 전 검증**: `AddressValidationService`를 구현하여 EVM/Solana 주소 포맷이 대상 체인과 일치하는지 사전에 검증합니다.

---

### 2026-01-05: MetaMask 딥링크 처리 및 WalletConnect Relay 안정성 강화

**기능**: MetaMask 딥링크 연동을 고도화하고, 앱 생명주기 변경 시 WalletConnect Relay 연결 안정성을 개선했습니다.

**주요 개선 사항**:
1.  **MetaMask 딥링크 연동 강화**:
    *   **강력한 딥링크 핸들링**: MetaMask를 위한 포괄적인 딥링크 핸들러 구현.
    *   **상태 관리**: 콜백 처리 중 무한 루프나 경쟁 상태를 방지하기 위한 상태 플래그 추가.
2.  **WalletConnect Relay 안정성**:
    *   **백그라운드 재연결 초기화**: 앱이 포그라운드로 복귀할 때 새로운 재연결 시도를 허용.
    *   **Fail-Fast 로직**: `ensureRelayConnected`가 에러 이벤트 발생 시 즉시 실패하도록 수정.

---

### 2025-12-31: WalletConnect 세션 레지스트리 및 멀티 세션 아키텍처 강화

**기능**: 여러 WalletConnect 세션을 중앙에서 체계적으로 관리하기 위한 `WalletConnectSessionRegistry` 도입 및 관련 데이터 모델/어댑터 리팩토링.

**주요 개선 사항**:
1.  **WalletConnectSessionRegistry 도입**:
    *   다중 세션의 생명주기(Active, Inactive, Stale, Expired)를 중앙에서 관리하는 전용 레지스트리 구현.
    *   세션 전환(Switching), 검증(Validation), 만료 정리(Cleanup) 로직 통합.
2.  **데이터 모델 고도화**:
    *   `PersistedSession`: 메타데이터 필드 추가로 UI 표현력 강화.
    *   `MultiSessionModel` & `PersistedSessionModel`: 직렬화/역직렬화 로직 개선.
3.  **어댑터 리팩토링**:
    *   `WalletConnectAdapter`, `TrustWalletAdapter`, `OKXWalletAdapter`: 새로운 세션 모델 및 레지스트리 구조에 맞춰 업데이트.

---

### 2025-12-31: Coinbase 세션 지속성 수정 및 세션 복원 안정화

**기능**: Coinbase 지갑의 세션이 앱 재시작 후에도 유지되지 않던 문제를 해결하고, 세션 복원 아키텍처를 개선했습니다.

**개선된 세션 관리 아키텍처**:

| 지갑 유형 | 저장 방식 | 복원 전략 |
|-----------|-----------|-----------|
| Coinbase | `CoinbaseSessionModel` (FlutterSecureStorage) | 주소/chainId 기반 상태 복원 - SDK stateless |
| MetaMask/Trust/OKX | `PersistedSessionModel` (FlutterSecureStorage) + AppKit 내부 스토리지 | Topic 기반 세션 복원 (AppKit 의존) |
| Phantom | `PhantomSessionModel` (FlutterSecureStorage) | 암호화 키 기반 세션 복원 |

---

### 2025-12-30: OKX 지갑 연결 안정성 대폭 개선

**기능**: OKX 지갑 연결 시 발생하던 두 가지 주요 문제를 해결했습니다.

**해결된 문제**:
1.  **Phase 1: 승인 팝업 미표시 문제** - Android에서 표준 `wc:` 스키마를 최우선 사용하도록 수정
2.  **Phase 2: 승인 후 앱 복귀 시 크래시** - 중복 재연결 방지 및 재시도 로직 강화

---

### 2025-12-29: 세션 복원 안정성 및 오프라인 모드 강화

**기능**: 세션 복원 프로세스의 안정성을 대폭 강화하고, 오프라인 상태에서도 캐시된 지갑 정보를 표시하며, 상세한 메트릭 수집 및 보안 로깅을 도입했습니다.

**주요 개선 사항**:
1.  **세션 복원 안정성 강화**: Exponential Backoff, 사전 유효성 검사, 타임아웃 및 부분 성공 처리
2.  **오프라인 모드 지원**: 캐시된 지갑 정보 표시, 네트워크 복구 시 자동 재연결
3.  **상세 UI/UX 개선**: 개별 지갑 상태 표시, 재시도 옵션
4.  **운영 및 보안 강화**: Production-Safe Logger, Sentry 메트릭

---

### 2025-12-24: Phantom 지갑 레거시 세션 마이그레이션 및 복원 강화

**기능**: 기존 단일 세션 저장소에 저장된 Phantom 지갑 데이터를 새로운 Multi-Session 아키텍처로 안전하게 이관.

---

### 2025-12-24: 세션 복원 UX 개선 (Skeleton UI & Splash)

**기능**: 앱 Cold Start 시 저장된 세션 복원 과정을 시각적으로 표시하여 사용자 경험을 크게 개선했습니다.

**주요 개선 사항**:
- Session Restoration Provider 및 Splash
- Skeleton UI 위젯 (WalletCardSkeleton, ConnectedWalletsSkeleton)
- Shimmer 위젯 라이브러리
- 부드러운 전환 애니메이션

---

### 2025-12-23: Phantom 지갑 SIWS (Sign In With Solana) 자동 트리거 구현

- **기능**: Phantom 지갑 연결 성공 직후, 자동으로 `signInWithSolana`를 호출하여 지갑 소유권을 암호학적으로 증명합니다.

### 2025-12-23: OKX 지갑 무한 로딩 해결 (Optimistic Session Check)

- **문제 해결**: OKX 지갑에서 승인 후 앱으로 복귀했을 때, WebSocket Relay 연결이 끊어져 무한 로딩에 빠지는 문제를 해결했습니다.

### 2025-12-23: 멀티 세션 관리 구조 도입 (Foundation)

- **MultiSessionState**: 여러 지갑의 세션을 동시에 관리하기 위한 상태 모델을 도입했습니다.

### 2025-12-23: Sentry 기반 로깅 및 연결 복구 UX

- **Sentry 도입**: 지갑 연결 실패 및 예외 상황을 체계적으로 추적합니다.
- **복구 옵션**: 연결 승인이 지연되거나 실패할 경우, 사용자에게 재시도, QR 코드 복사 등의 복구 옵션을 제공합니다.

---

## 참고 자료

- [Flutter 문서](https://docs.flutter.dev/)
- [WalletConnect v2 문서](https://docs.walletconnect.com/)
- [Reown AppKit](https://docs.reown.com/)
- [Phantom Deep Links](https://docs.phantom.app/solana/deep-links)
