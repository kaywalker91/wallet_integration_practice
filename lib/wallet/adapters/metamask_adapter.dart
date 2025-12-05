import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';

/// MetaMask wallet adapter (extends WalletConnect with deep linking)
class MetaMaskAdapter extends WalletConnectAdapter {
  MetaMaskAdapter({WalletAdapterConfig? config}) : super(config: config);

  @override
  WalletType get walletType => WalletType.metamask;

  /// Check if MetaMask is installed
  Future<bool> isMetaMaskInstalled() async {
    try {
      final uri = Uri.parse(WalletConstants.metamaskDeepLink);
      return await canLaunchUrl(uri);
    } catch (e) {
      return false;
    }
  }

  /// Open MetaMask app
  Future<bool> openMetaMask() async {
    try {
      final uri = Uri.parse(WalletConstants.metamaskDeepLink);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening MetaMask', e);
      return false;
    }
  }

  /// Open MetaMask with WalletConnect URI
  Future<bool> openWithUri(String wcUri) async {
    try {
      // Encode the WalletConnect URI for MetaMask deep link
      final encodedUri = Uri.encodeComponent(wcUri);
      final deepLink = 'metamask://wc?uri=$encodedUri';

      final uri = Uri.parse(deepLink);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // Fallback to app store if not installed
        await _openAppStore();
      }

      return launched;
    } catch (e) {
      AppLogger.e('Error opening MetaMask with URI', e);
      return false;
    }
  }

  Future<void> _openAppStore() async {
    try {
      String storeUrl;
      if (Platform.isIOS) {
        storeUrl =
            'https://apps.apple.com/app/id${WalletConstants.metamaskAppStoreId}';
      } else if (Platform.isAndroid) {
        storeUrl =
            'https://play.google.com/store/apps/details?id=${WalletConstants.metamaskPackageAndroid}';
      } else {
        return;
      }

      final uri = Uri.parse(storeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening app store', e);
    }
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    // First, get the WalletConnect URI
    await initialize();

    // Start the connection process
    final completer = Completer<WalletEntity>();

    // Subscribe to connection stream
    final subscription = connectionStream.listen((status) {
      if (status.isConnected && status.wallet != null) {
        if (!completer.isCompleted) {
          completer.complete(status.wallet!.copyWith(type: walletType));
        }
      } else if (status.hasError) {
        if (!completer.isCompleted) {
          completer.completeError(
            WalletException(
              message: status.errorMessage ?? 'Connection failed',
              code: 'CONNECTION_ERROR',
            ),
          );
        }
      }
    });

    try {
      // Generate connection URI via parent class
      super.connect(chainId: chainId, cluster: cluster);

      // Wait a moment for URI to be generated
      await Future.delayed(const Duration(milliseconds: 500));

      final uri = await getConnectionUri();
      if (uri != null) {
        // Open MetaMask with the URI
        await openWithUri(uri);
      }

      // Wait for connection with timeout
      final wallet = await completer.future.timeout(
        AppConstants.connectionTimeout,
        onTimeout: () {
          throw WalletException(
            message: 'Connection timed out',
            code: 'TIMEOUT',
          );
        },
      );

      return wallet;
    } finally {
      await subscription.cancel();
    }
  }
}
