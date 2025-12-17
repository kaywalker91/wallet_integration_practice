import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/coinbase_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/generic_wallet_connect_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/metamask_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/okx_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/phantom_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/rabby_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/trust_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';

import '../../core/constants/wallet_constants.dart';

/// Factory for creating wallet adapters.
///
/// This factory encapsulates the logic for instantiating specific wallet adapters
/// based on the [WalletType]. It promotes the Open/Closed Principle by isolating
/// adapter creation logic.
class WalletAdapterFactory {
  /// Create a new instance of a wallet adapter.
  static BaseWalletAdapter createAdapter(
    WalletType type,
    WalletAdapterConfig config,
  ) {
    switch (type) {
      case WalletType.metamask:
        return MetaMaskAdapter(config: config);
      case WalletType.walletConnect:
        return GenericWalletConnectAdapter(config: config);
      case WalletType.phantom:
        return PhantomAdapter();
      case WalletType.trustWallet:
        return TrustWalletAdapter(config: config);
      case WalletType.rabby:
        return RabbyWalletAdapter(config: config);
      case WalletType.okxWallet:
        return OkxWalletAdapter(config: config);
      case WalletType.coinbase:
        return CoinbaseWalletAdapter(config: config);
      case WalletType.rainbow:
        return WalletConnectAdapter(config: config);
    }
  }
}
