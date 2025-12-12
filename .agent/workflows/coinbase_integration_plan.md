---
description: Plan to integrate Coinbase Wallet
---

# Coinbase Wallet Integration Plan

This workflow outlines the steps to integrate Coinbase Wallet into the application, replacing the generic WalletConnect usage with a dedicated adapter for better deep link control.

## 1. Create Coinbase Wallet Adapter
Create a new file `lib/wallet/adapters/coinbase_wallet_adapter.dart` that extends `WalletConnectAdapter`.

### Key Implementation Details:
- **Class**: `CoinbaseWalletAdapter`
- **Inherits**: `WalletConnectAdapter`
- **WalletType**: `WalletType.coinbase`
- **Deep Link Strategies** (in `openWithUri`):
    1.  **Universal Link**: `https://go.cb-w.com/wallet-connect?uri={encodedUri}` (Preferred)
    2.  **Custom Scheme**: `cbwallet://wcc?uri={encodedUri}`
    3.  **Legacy Scheme**: `cbwallet://wc?uri={encodedUri}`
    4.  **Fallback**: `wc://`

### Code Template:
```dart
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';
// ... imports

class CoinbaseWalletAdapter extends WalletConnectAdapter {
  CoinbaseWalletAdapter({super.config});

  @override
  WalletType get walletType => WalletType.coinbase;

  // Implement isInstalled using WalletConstants.coinbaseDeepLink
  
  // Implement openWithUri using appropriate strategies
}
```

## 2. Register Adapter in WalletService
Update `lib/wallet/services/wallet_service.dart` to use the new adapter.

### Changes:
- **Import**: Import `coinbase_wallet_adapter.dart`.
- **Factory**: Update `_createAdapter` switch case for `WalletType.coinbase` to return `CoinbaseWalletAdapter(config: _config)`.
- **Deep Link Handler**: Add a handler for `coinbase` in `_setupDeepLinkHandlers`.
  ```dart
  deepLinkService.registerHandler('coinbase', (uri) async {
      // ... logging and handling
  });
  ```

## 3. Verify Assets
Ensure `assets/icons/coinbase.png` exists. If not, create a placeholder or ask the user to provide one.

## 4. Testing
- Build and run the app.
- Select Coinbase Wallet from the wallet list.
- Verify deep linking opens the Coinbase Wallet app.
- Verify connection approval works and session is established.
