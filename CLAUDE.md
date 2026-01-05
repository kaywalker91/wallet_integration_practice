# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-chain wallet integration prototype for iLity Hub. Flutter app supporting EVM chains (Ethereum, Polygon, Arbitrum, Optimism, Base, BNB, ILITY) and Solana via multiple wallet providers.

### Supported Wallets

| Wallet | EVM | Solana | Connection Type |
|--------|-----|--------|-----------------|
| MetaMask | ✓ | - | WalletConnect + Deep Link |
| WalletConnect | ✓ | - | WalletConnect Protocol |
| Coinbase | ✓ | ✓ | Native SDK |
| OKX Wallet | ✓ | ✓ | WalletConnect + Deep Link |
| Trust Wallet | ✓ | ✓ | WalletConnect |
| Rainbow | ✓ | - | WalletConnect |
| Phantom | ✓ | ✓ | Native SDK (Solana) |
| Rabby | ✓ | - | WalletConnect |

## Build & Development Commands

```bash
# Get dependencies
flutter pub get

# Run code generation (freezed, json_serializable, riverpod_generator)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run

# Run tests
flutter test

# Run single test file
flutter test test/widget_test.dart

# Analyze code
flutter analyze

# Format code
dart format .
```

## Architecture

### Layer Structure (Clean Architecture)

```
lib/
├── core/              # Shared utilities, constants, errors, services
│   ├── constants/     # App, chain, wallet constants
│   ├── errors/        # Typed failures and exceptions
│   ├── services/      # DeepLink, Connectivity, Logging services
│   ├── utils/         # Address validation, crypto, backoff utilities
│   └── models/        # Log enums and models
├── data/              # Data layer
│   ├── datasources/   # Local (cache, sessions) & Remote (RPC)
│   ├── models/        # Persisted session models
│   └── repositories/  # Repository implementations
├── domain/            # Business logic
│   ├── entities/      # Core entities (Wallet, Session, Balance)
│   ├── repositories/  # Repository interfaces
│   └── usecases/      # Business use cases
├── wallet/            # Wallet integration layer
│   ├── adapters/      # Wallet-specific adapters
│   ├── services/      # WalletService, SessionRegistry, Factory
│   ├── models/        # Adapter configs, session results
│   └── utils/         # Topic validation utilities
└── presentation/      # UI layer
    ├── providers/     # Riverpod state management
    ├── screens/       # Screen widgets
    └── widgets/       # Reusable UI components
```

Each layer has a barrel export file (e.g., `core/core.dart`) for clean imports.

### Wallet Adapter Pattern

The wallet integration uses an adapter pattern with a common interface:

**Base Classes:**
- `BaseWalletAdapter` - Abstract base class defining common wallet operations
- `EvmWalletAdapter` - Extended interface for EVM-specific operations (switchChain, signTypedData)
- `SolanaWalletAdapter` - Extended interface for Solana operations (signSolanaTransaction)

**Concrete Adapters:**
- `WalletConnectAdapter` - Generic WalletConnect v2 implementation
- `MetaMaskAdapter` - MetaMask-specific with deep link handling
- `PhantomAdapter` - Phantom native SDK for Solana
- `CoinbaseWalletAdapter` - Coinbase native SDK
- `OKXWalletAdapter` - OKX with aggressive reconnection config
- `TrustWalletAdapter` - Trust Wallet via WalletConnect
- `RabbyWalletAdapter` - Rabby via WalletConnect
- `GenericWalletConnectAdapter` - Fallback for other WalletConnect wallets

**Key Services:**
- `WalletService` - Manages adapter lifecycle, routes operations to active adapter
- `WalletAdapterFactory` - Creates appropriate adapter based on WalletType
- `WalletConnectSessionRegistry` - Manages multi-session state with validation

### State Management

Uses Riverpod with providers defined in `presentation/providers/`:

**Core Providers:**
- `walletServiceProvider` - Singleton WalletService instance
- `walletNotifierProvider` - StateNotifier for single wallet operations
- `multiWalletNotifierProvider` - Multi-wallet state management

**Connection Providers:**
- `walletConnectionStreamProvider` - Stream of connection status updates
- `connectedWalletProvider` - Current connected wallet entity
- `connectedWalletsProvider` - List of all connected wallets

**Session Providers:**
- `sessionAccountsProvider` - Multi-account session support
- `activeAccountNotifierProvider` - Active account selection
- `sessionRestorationProvider` - Session restoration on app launch

**Recovery Providers:**
- `connectionRecoveryProvider` - Connection recovery state
- `walletRetryStatusProvider` - Retry status tracking

### Key Entities

- `WalletEntity` - Connected wallet state (address, type, chainId/cluster, sessionTopic)
- `WalletConnectionStatus` - Connection state with retry info and progress messages
- `ChainInfo` - Blockchain network configuration (chainId, cluster, rpcUrl)
- `WalletType` enum - Supported wallet types with deep link schemes and capabilities
- `PersistedSession` / `ManagedSession` - Session persistence and validation
- `SessionAccount` - Individual account within a session (multi-account support)

### Error Handling

Typed failures in `core/errors/failures.dart`:

| Failure Type | Description |
|--------------|-------------|
| `WalletConnectionFailure` | Connection issues (timeout, rejected, notInstalled, sessionExpired) |
| `SignatureFailure` | Transaction signing errors (rejected, timeout, invalidParams) |
| `ChainFailure` | Chain switching problems (unsupportedChain, switchFailed) |
| `NetworkFailure` | Network connectivity issues (noConnection, serverError, timeout) |
| `StorageFailure` | Local storage errors (readFailed, writeFailed) |
| `BalanceFailure` | Balance fetch errors (rpcError, invalidAddress, addressChainMismatch) |

Exceptions in `core/errors/exceptions.dart` with `WalletException` as the primary exception type.

### Session Management

**Multi-Session Architecture:**
- `WalletConnectSessionRegistry` - Central registry for all WalletConnect sessions
- `MultiSessionDataSource` - Persistent storage for multiple wallet sessions
- `ManagedSession` - Session with state tracking (active, inactive, stale, expired)
- Session validation on app resume with automatic cleanup of expired sessions

**Session States:**
```dart
enum SessionState { active, inactive, stale, expired }
```

### Connectivity & Recovery

- `ConnectivityService` - Network status monitoring (online, offline, unknown)
- `ExponentialBackoff` - Retry logic with configurable backoff
- `WalletReconnectionConfig` - Per-wallet reconnection strategies (aggressive, medium, lenient, standard)
- `RelayConnectionState` - WalletConnect relay connection status tracking

### Deep Link Flow

`DeepLinkService` (singleton) handles wallet callbacks. Registered handlers in `WalletNotifier` route URIs to appropriate adapters based on host/path.

**Deep Link Schemes:**
- MetaMask: `metamask://`
- Coinbase: `cbwallet://`
- OKX Wallet: `okxwallet://`
- Trust Wallet: `trust://`
- Phantom: `phantom://`
- Rabby: `rabby://`
- Rainbow: `rainbow://`

## Key Constants

- WalletConnect Project ID in `core/constants/app_constants.dart`
- Chain IDs and RPC URLs in `core/constants/chain_constants.dart`
- Wallet deep link schemes in `core/constants/wallet_constants.dart`
- Expected failure codes (non-error user behaviors) in `WalletConstants.expectedFailureCodes`

## Multi-Chain Support

**EVM Chains** (use `chainId: int`):
- Ethereum (1), Sepolia (11155111)
- Polygon (137), Amoy (80002)
- BNB Chain (56, 97)
- Arbitrum One (42161), Sepolia (421614)
- Optimism (10), Sepolia (11155420)
- Base (8453), Sepolia (84532)
- ILITY (999999 - placeholder)

**Solana** (use `cluster: String`):
- mainnet-beta, devnet, testnet

The `ChainType` enum distinguishes between chain families (evm, solana, sui).

## Utility Services

- `AddressValidationService` - Address format validation for EVM/Solana
- `CryptoIsolate` - Cryptographic operations in isolate for performance
- `TopicValidator` - WalletConnect topic validation
- `WalletLogService` / `DebugLogService` - Structured logging with context
- `SentryService` - Error reporting with expected failure filtering
- `PendingConnectionService` - Track pending wallet connections
