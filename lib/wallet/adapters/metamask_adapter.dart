import 'dart:async';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// MetaMask wallet adapter (extends WalletConnect with deep linking)
class MetaMaskAdapter extends WalletConnectAdapter {
  MetaMaskAdapter({super.config});

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
  /// Throws [WalletNotInstalledException] if MetaMask is not installed
  Future<bool> openWithUri(String wcUri) async {
    try {
      // 1. Try Custom Scheme (metamask://)
      // This is preferred as it opens the app directly if installed
      final encodedUri = Uri.encodeComponent(wcUri);
      final schemeUrl = 'metamask://wc?uri=$encodedUri';
      final schemeUri = Uri.parse(schemeUrl);

      // Check if scheme calls are supported/can be handled
      if (await canLaunchUrl(schemeUri)) {
        final launched = await launchUrl(
          schemeUri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) return true;
      }

      // 2. Try Universal Link (HTTPS)
      // This serves as a fallback that handles "open app or go to store" logic usually
      final universalUrl = 'https://metamask.app.link/wc?uri=$encodedUri';
      final universalUri = Uri.parse(universalUrl);
      
      final launchedUniversal = await launchUrl(
        universalUri,
        mode: LaunchMode.externalApplication,
      );

      if (launchedUniversal) return true;

      // 3. Both failed - assume not installed
      throw WalletNotInstalledException(
        walletType: walletType.name,
        message: 'MetaMask is not installed',
      );
    } catch (e) {
      if (e is WalletNotInstalledException) rethrow;
      AppLogger.e('Error opening MetaMask with URI', e);
      throw WalletNotInstalledException(
        walletType: walletType.name,
        message: 'Failed to open MetaMask: ${e.toString()}',
      );
    }
  }

  @override
  bool isSessionValid(SessionData session) {
    final name = session.peer.metadata.name.toLowerCase();
    final isValid = name.contains('metamask');
    if (!isValid) {
      AppLogger.d('MetaMaskAdapter ignored session for: $name');
    }
    return isValid;
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    // Ensure adapter is initialized
    await initialize();

    try {
      // Step 1: Prepare connection (generates URI without blocking on approval)
      final sessionFuture = await prepareConnection(chainId: chainId);

      // Step 2: Get the generated URI
      final uri = await getConnectionUri();
      if (uri == null) {
        throw const WalletException(
          message: 'Failed to generate WalletConnect URI for MetaMask',
          code: 'URI_GENERATION_FAILED',
        );
      }

      AppLogger.wallet('Opening MetaMask with URI', data: {
        'uri': uri.substring(0, uri.length.clamp(0, 50)),
      });

      // Step 3: Open MetaMask with the URI
      await openWithUri(uri);

      // Step 4: Wait for session approval with timeout
      final wallet = await sessionFuture.timeout(
        AppConstants.connectionTimeout,
        onTimeout: () {
          throw const WalletException(
            message: 'Connection timed out waiting for MetaMask approval',
            code: 'TIMEOUT',
          );
        },
      );

      // Return wallet with correct type
      return wallet.copyWith(type: walletType);
    } catch (e) {
      // Don't log expected failures as errors (reduces log noise)
      if (e is WalletException &&
          WalletConstants.expectedFailureCodes.contains(e.code)) {
        AppLogger.wallet('MetaMask connection cancelled/timeout', data: {
          'code': e.code,
        });
      } else {
        AppLogger.e('MetaMask connection error', e);
      }
      rethrow;
    }
  }
}
