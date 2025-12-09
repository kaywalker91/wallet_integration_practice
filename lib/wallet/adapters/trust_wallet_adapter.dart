import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Trust Wallet adapter (extends WalletConnect with deep linking)
class TrustWalletAdapter extends WalletConnectAdapter {
  TrustWalletAdapter({super.config});

  @override
  WalletType get walletType => WalletType.trustWallet;

  /// Check if Trust Wallet is installed
  Future<bool> isTrustWalletInstalled() async {
    try {
      final uri = Uri.parse(WalletConstants.trustWalletDeepLink);
      return await canLaunchUrl(uri);
    } catch (e) {
      return false;
    }
  }

  /// Open Trust Wallet app
  Future<bool> openTrustWallet() async {
    try {
      final uri = Uri.parse(WalletConstants.trustWalletDeepLink);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening Trust Wallet', e);
      return false;
    }
  }

  /// Open Trust Wallet with WalletConnect URI
  /// Throws [WalletNotInstalledException] if Trust Wallet is not installed
  Future<bool> openWithUri(String wcUri) async {
    try {
      // Encode the WalletConnect URI for Trust Wallet deep link
      final encodedUri = Uri.encodeComponent(wcUri);
      final deepLink = 'trust://wc?uri=$encodedUri';

      final uri = Uri.parse(deepLink);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // launchUrl returned false = app not installed
        throw WalletNotInstalledException(
          walletType: walletType.name,
          message: 'Trust Wallet is not installed',
        );
      }

      return true;
    } catch (e) {
      if (e is WalletNotInstalledException) rethrow;
      AppLogger.e('Error opening Trust Wallet with URI', e);
      throw WalletNotInstalledException(
        walletType: walletType.name,
        message: 'Failed to open Trust Wallet: ${e.toString()}',
      );
    }
  }

  Future<void> _openAppStore() async {
    try {
      String storeUrl;
      if (Platform.isIOS) {
        storeUrl =
            'https://apps.apple.com/app/id${WalletConstants.trustWalletAppStoreId}';
      } else if (Platform.isAndroid) {
        storeUrl =
            'https://play.google.com/store/apps/details?id=${WalletConstants.trustWalletPackageAndroid}';
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
        // Open Trust Wallet with the URI
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
