import 'dart:async' show Completer, StreamSubscription, unawaited;
import 'dart:io';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Coinbase Wallet adapter (extends WalletConnect with specialized deep linking)
///
/// Handles connection with Coinbase Wallet (Self-Custody) via WalletConnect,
/// using proper Universal Links and Custom Schemes for mobile redirection.
class CoinbaseWalletAdapter extends WalletConnectAdapter {
  CoinbaseWalletAdapter({super.config});

  @override
  WalletType get walletType => WalletType.coinbase;

  /// Check if Coinbase Wallet is installed
  Future<bool> isCoinbaseInstalled() async {
    try {
      final uri = Uri.parse(WalletConstants.coinbaseDeepLink);
      final canLaunch = await canLaunchUrl(uri);
      AppLogger.wallet('Coinbase installed check', data: {'installed': canLaunch});
      return canLaunch;
    } catch (e) {
      AppLogger.e('Error checking Coinbase installation', e);
      return false;
    }
  }

  /// Open Coinbase Wallet app
  Future<bool> openCoinbase() async {
    try {
      final uri = Uri.parse(WalletConstants.coinbaseDeepLink);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening Coinbase Wallet', e);
      return false;
    }
  }

  /// Open Coinbase Wallet with WalletConnect URI
  ///
  /// Strategy order:
  /// 1. https://go.cb-w.com/wallet-connect?uri=... (Universal Link - Preferred)
  /// 2. cbwallet://wcc?uri=... (Current Custom Scheme)
  /// 3. cbwallet://wc?uri=... (Legacy Custom Scheme)
  /// 4. wc:// scheme (OS fallback)
  Future<bool> openWithUri(String wcUri) async {
    AppLogger.wallet('Attempting to open Coinbase with WC URI', data: {
      'uriLength': wcUri.length,
      'uriPrefix': wcUri.substring(0, wcUri.length > 50 ? 50 : wcUri.length),
    });

    final encodedUri = Uri.encodeComponent(wcUri);

    // Strategy 1: Standard Custom Scheme (Android Preferred)
    // cbwallet://wc?uri={uri}
    try {
      final wcUrl = 'cbwallet://wc?uri=$encodedUri';
      final uri = Uri.parse(wcUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched Coinbase wc scheme');
        return true;
      }
    } catch (e) {
      AppLogger.w('Coinbase wc scheme failed: $e');
    }

    // Strategy 2: Universal Link (Standard)
    // https://go.cb-w.com/wc?uri={uri}
    try {
      final universalUrl = 'https://go.cb-w.com/wc?uri=$encodedUri';
      final uri = Uri.parse(universalUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched Coinbase Universal Link (wc path)');
        return true;
      }
    } catch (e) {
      AppLogger.w('Coinbase Universal Link failed: $e');
    }

    // Strategy 3: Alternative Custom Scheme
    // cbwallet://wcc?uri={uri}
    try {
      final wccUrl = 'cbwallet://wcc?uri=$encodedUri';
      final uri = Uri.parse(wccUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched Coinbase wcc scheme');
        return true;
      }
    } catch (e) {
      AppLogger.w('Coinbase wcc scheme failed: $e');
    }

    // Strategy 4: wc:// fallback
    try {
      final wcSchemeUri = wcUri.replaceFirst('wc:', 'wc://');
      final uri = Uri.parse(wcSchemeUri);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched via wc:// scheme');
        return true;
      }
    } catch (e) {
      AppLogger.w('wc:// scheme launch failed: $e');
    }

    AppLogger.w('All Coinbase deep link strategies failed');
    throw WalletNotInstalledException(
      walletType: walletType.name,
      message: 'Coinbase Wallet is not installed or does not support deep linking',
    );
  }

  /// Wait for URI to be generated with polling
  Future<String?> _waitForUri({
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 200),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      final uri = await getConnectionUri();
      if (uri != null && uri.isNotEmpty) {
        AppLogger.wallet('URI obtained', data: {
          'waitTime': '${stopwatch.elapsedMilliseconds}ms',
        });
        return uri;
      }
      await Future.delayed(pollInterval);
    }

    AppLogger.w('URI generation timed out after ${timeout.inSeconds}s');
    return null;
  }

  @override
  bool isSessionValid(SessionData session) {
    final name = session.peer?.metadata.name.toLowerCase() ?? '';
    // Allow 'coinbase' or generic if needed, but filtering helps avoid cross-wallet confusion
    return name.contains('coinbase') || name.contains('toshi');
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    AppLogger.wallet('CoinbaseWalletAdapter.connect() started');

    await initialize();

    if (isConnected && connectedAddress != null) {
      AppLogger.wallet('Reusing existing session');
      return WalletEntity(
        address: connectedAddress!,
        type: walletType,
        chainId: requestedChainId ?? currentChainId,
        connectedAt: DateTime.now(),
      );
    }

    final completer = Completer<WalletEntity>();
    StreamSubscription? subscription;

    subscription = connectionStream.listen(
      (status) {
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
      },
      onError: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
    );

    try {
      // Start connection (generates URI)
      unawaited(super.connect(chainId: chainId, cluster: cluster));

      // Wait for URI
      final uri = await _waitForUri();

      if (uri == null) {
        throw const WalletException(
          message: 'Failed to generate connection URI',
          code: 'URI_GENERATION_FAILED',
        );
      }

      // Open Coinbase Wallet
      await openWithUri(uri);

      // Wait for specific connection approval
      AppLogger.wallet('Waiting for Coinbase approval...');
      final wallet = await completer.future.timeout(
        AppConstants.connectionTimeout,
        onTimeout: () {
          throw const WalletException(
            message: 'Connection timed out. Please approve in Coinbase Wallet.',
            code: 'TIMEOUT',
          );
        },
      );

      return wallet;
    } catch (e) {
      AppLogger.e('Coinbase connection failed', e);
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }
}
