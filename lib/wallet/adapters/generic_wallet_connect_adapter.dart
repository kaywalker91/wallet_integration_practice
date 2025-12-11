import 'dart:async';

import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Generic WalletConnect adapter (extends WalletConnectAdapter)
///
/// Handles generic WalletConnect connection by launching the 'wc:' scheme.
/// This allows the user to choose any installed wallet that supports WalletConnect
/// via the Android "Open with" dialog, or opens the default handler.
class GenericWalletConnectAdapter extends WalletConnectAdapter {
  GenericWalletConnectAdapter({super.config});

  @override
  WalletType get walletType => WalletType.walletConnect;

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    AppLogger.wallet('GenericWalletConnectAdapter.connect() started');

    await initialize();

    if (isConnected) {
      AppLogger.wallet('Disconnecting existing session to force new connection');
      await disconnect();
    }

    try {
      // Just call super.connect().
      // This will generate the URI and wait for connection.
      // The UI is responsible for retrieving the URI via getConnectionUri()
      // and displaying it (QR Code) or launching it.
      return await super.connect(chainId: chainId, cluster: cluster);
    } catch (e) {
      AppLogger.e('Generic WalletConnect connection failed', e);
      rethrow;
    }
  }
}
