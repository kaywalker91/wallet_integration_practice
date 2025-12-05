# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Multi-chain wallet integration prototype for iLity Hub. Flutter app supporting EVM chains (Ethereum, Polygon, Arbitrum, Optimism, Base, BNB) and Solana via WalletConnect, MetaMask, Phantom, and other wallets.

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
├── core/          # Shared utilities, constants, errors, services
├── data/          # Data layer (models, datasources)
├── domain/        # Business logic (entities, repositories, usecases)
├── wallet/        # Wallet integration layer (adapters, services)
└── presentation/  # UI layer (screens, widgets, providers)
```

Each layer has a barrel export file (e.g., `core/core.dart`) for clean imports.

### Wallet Adapter Pattern

The wallet integration uses an adapter pattern with a common interface:

- `BaseWalletAdapter` - Abstract base class defining wallet operations
- `EvmWalletAdapter` - Extended interface for EVM-specific operations
- `SolanaWalletAdapter` - Extended interface for Solana-specific operations
- Concrete adapters: `WalletConnectAdapter`, `MetaMaskAdapter`, `PhantomAdapter`

`WalletService` manages adapter lifecycle and routes operations to the active adapter.

### State Management

Uses Riverpod with providers defined in `presentation/providers/`:

- `walletServiceProvider` - Singleton WalletService instance
- `walletNotifierProvider` - StateNotifier for wallet operations
- `walletConnectionStreamProvider` - Stream of connection status updates
- `connectedWalletProvider` - Current connected wallet entity

### Key Entities

- `WalletEntity` - Connected wallet state (address, type, chainId/cluster)
- `WalletConnectionStatus` - Connection state with retry info
- `ChainInfo` - Blockchain network configuration
- `WalletType` enum - Supported wallet types with deep link schemes

### Error Handling

Typed failures in `core/errors/failures.dart`:
- `WalletConnectionFailure` - Connection issues
- `SignatureFailure` - Transaction signing errors
- `ChainFailure` - Chain switching problems

Exceptions in `core/errors/exceptions.dart` with `WalletException` as the primary exception type.

### Deep Link Flow

`DeepLinkService` (singleton) handles wallet callbacks. Registered handlers in `WalletNotifier` route URIs to appropriate adapters based on host/path.

## Key Constants

- WalletConnect Project ID in `core/constants/app_constants.dart`
- Chain IDs and RPC URLs in `core/constants/chain_constants.dart`
- Wallet deep link schemes in `core/constants/wallet_constants.dart`

## Multi-Chain Support

EVM chains use `chainId` (int), Solana uses `cluster` (string: mainnet-beta, devnet, testnet). The `ChainType` enum distinguishes between chain families.
