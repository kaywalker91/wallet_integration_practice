# wallet_integration_practice

Wallet Integration Practice for iLity Hub

## Features

- Multi-chain wallet support (EVM chains + Solana)
- WalletConnect v2 integration
- Deep link wallet connection flow
- Supported wallets: MetaMask, Trust Wallet, Phantom, Rabby, OKX Wallet

## Recent Changes

### 2024-12-10: Fix infinite loading on wallet return

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