# wallet_integration_practice

Wallet Integration Practice for iLity Hub

## Features

- Multi-chain wallet support (EVM chains + Solana)
- WalletConnect v2 integration
- Deep link wallet connection flow
- Supported wallets: MetaMask, Trust Wallet, Phantom, Rabby, OKX Wallet

## Recent Changes

### 2025-12-16: Rabby Wallet UX & dApp URL Configuration

**Feature**: Improved Rabby Wallet connection flow and updated dApp URL configuration.

**Changes**:
- **Rabby Wallet**: Re-enabled dedicated guide dialog for Rabby Wallet users, as it requires a manual dApp browser connection flow instead of standard deep linking.
- **UI Text**: Updated Rabby Wallet guide text to correctly refer to the "Dapps" tab instead of "Browser".
- **Configuration**: Updated `dappUrl` to point to the active development environment for better integration testing.

**Files Changed**:
- `lib/core/constants/app_constants.dart`
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart`
- `lib/presentation/screens/onboarding/rabby_guide_dialog.dart`

---

### 2025-12-16: Trust Wallet Connection UX Improvement

**Problem**: Trust Wallet 연결 시 최종적으로 연결 성공하지만, 중간에 "연결 실패" 메시지가 일시적으로 표시되는 문제.

**Root Cause**: `_restoreAndCheckSession()` 메서드에서 relay 재연결 후 세션이 즉시 발견되지 않으면 에러 UI를 바로 표시. Trust Wallet은 세션 동기화가 느려서 500ms 대기 후에도 세션이 준비되지 않을 수 있지만, retry 로직이 작동하면 결국 연결됨.

**Solution**:
1. `_restoreAndCheckSession()`에서 즉시 에러 UI 표시 대신 "서명 검증 중" 상태 유지
2. `clearPendingConnection()` 조기 호출 제거 → retry 로직이 계속 작동
3. 기존 스트림 리스너가 최종 연결 성공/실패 처리하도록 위임

**Expected Behavior**:
- 연결 중: "서명 검증 중" 상태 유지
- 연결 성공: 메인 화면으로 이동
- 진짜 연결 실패: timeout 후 에러 표시

**Files Changed**:
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart` - Removed premature error UI display

---

### 2025-12-16: OKX Wallet Connection Stability Fixes

**Problem 1**: OKX Wallet connection infinite approval loop after app cold start.

**Root Cause**: When Android kills the app process while user is in OKX Wallet, the WalletConnect WebSocket relay connection is lost but session objects persist in storage, causing a mismatch.

**Solution**:
1. Added relay state tracking and `ensureRelayConnected()` method in `WalletConnectAdapter`
2. Modified `_restoreSession()` to verify relay connection before restoring sessions
3. Added `initializeAdapter()` method in `WalletService` for restoration without new connection
4. Updated `OnboardingLoadingPage` to use relay reconnection flow

**Problem 2**: Black screen after returning from OKX Wallet on Samsung Galaxy devices.

**Root Cause**: Impeller (Vulkan) rendering engine compatibility issue with Mali GPU. Surface recreation fails on app resume.

**Solution**:
1. Disabled Impeller rendering engine (fallback to Skia/OpenGL)
2. Changed `launchMode` from `singleTop` to `singleTask` for stable Activity reuse
3. Added app-level `WidgetsBindingObserver` for forced UI redraw on resume

**Files Changed**:
- `android/app/src/main/AndroidManifest.xml` - Impeller disable, launchMode change
- `lib/main.dart` - Added lifecycle observer for UI redraw
- `lib/wallet/adapters/walletconnect_adapter.dart` - Relay reconnection support
- `lib/wallet/services/wallet_service.dart` - `initializeAdapter()` method
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart` - Restoration flow

---

### 2025-12-12: Coinbase Wallet Native SDK & Reown AppKit Integration

**Feature**: Migrated Coinbase Wallet integration to use native SDK and introduced Reown AppKit for unified WalletConnect handling.

**Changes**:
- **Coinbase Wallet**: Switched from generic WalletConnect to `coinbase_wallet_sdk` for better native experience on Android/iOS.
- **Reown AppKit**: Added `ReownAppKitService` to manage WalletConnect sessions, replacing custom implementation for better reliability and feature set.
- **Configuration**: Updated `AndroidManifest.xml` with required package visibility queries and deep link schemes for Coinbase Wallet.

**Files Changed**:
- `lib/wallet/adapters/coinbase_wallet_adapter.dart`
- `lib/wallet/services/reown_appkit_service.dart` (New)
- `android/app/src/main/AndroidManifest.xml`
- `pubspec.yaml`

### 2025-12-10: Fix infinite loading on wallet return

**Problem**: After approving connection in OKX Wallet and returning to the app, the onboarding screen would show infinite loading.

**Root Cause**:
- WalletConnect session events were emitted while the app was in background
- When the app resumed, the stream subscription had already missed the connection event
- The UI waited indefinitely for a stream event that would never come

**Solution**:
1. Added `currentConnectionStatus` getter to `WalletService` for synchronous status check
2. Modified `OnboardingLoadingPage` to check current connection status **before** subscribing to stream
3. Added `_restoreAndCheckSession()` for cold start recovery scenarios

**Files Changed**:
- `lib/wallet/services/wallet_service.dart` - Added `currentConnectionStatus` getter
- `lib/presentation/screens/onboarding/onboarding_loading_page.dart` - Immediate status check + restore logic

## Getting Started

### Prerequisites
- Flutter 3.x
- Dart 3.x

### Installation

```bash
# Get dependencies
flutter pub get

# Run code generation
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

### Build

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release
```

## Architecture

Clean Architecture with the following layers:

```
lib/
├── core/          # Shared utilities, constants, errors, services
├── data/          # Data layer (models, datasources)
├── domain/        # Business logic (entities, repositories, usecases)
├── wallet/        # Wallet integration layer (adapters, services)
└── presentation/  # UI layer (screens, widgets, providers)
```

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [WalletConnect v2 Docs](https://docs.walletconnect.com/)
- [Reown AppKit](https://docs.reown.com/)