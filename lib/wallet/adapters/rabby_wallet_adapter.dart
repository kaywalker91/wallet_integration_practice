import 'dart:async' show Completer, StreamSubscription, unawaited;
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Rabby Wallet adapter (extends WalletConnect with deep linking)
///
/// Rabby is an EVM-focused wallet developed by DeBank with features like
/// transaction simulation and portfolio tracking integration.
class RabbyWalletAdapter extends WalletConnectAdapter {
  RabbyWalletAdapter({super.config});

  @override
  WalletType get walletType => WalletType.rabby;

  /// Check if Rabby Wallet is installed
  Future<bool> isRabbyInstalled() async {
    try {
      final uri = Uri.parse(WalletConstants.rabbyDeepLink);
      final canLaunch = await canLaunchUrl(uri);
      AppLogger.wallet('Rabby installed check', data: {'installed': canLaunch});
      return canLaunch;
    } catch (e) {
      AppLogger.e('Error checking Rabby installation', e);
      return false;
    }
  }

  /// Open Rabby Wallet app
  Future<bool> openRabby() async {
    try {
      final uri = Uri.parse(WalletConstants.rabbyDeepLink);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening Rabby Wallet', e);
      return false;
    }
  }

  /// Open Rabby Wallet with WalletConnect URI
  /// Tries multiple deep link formats for compatibility
  Future<bool> openWithUri(String wcUri) async {
    AppLogger.wallet('Attempting to open Rabby with WC URI', data: {
      'uriLength': wcUri.length,
      'uriPrefix': wcUri.substring(0, wcUri.length > 50 ? 50 : wcUri.length),
    });

    // Try different deep link formats
    final deepLinkFormats = [
      // Standard WalletConnect format
      'rabby://wc?uri=${Uri.encodeComponent(wcUri)}',
      // Direct WC URI format
      'rabby://${wcUri.replaceFirst('wc:', '')}',
      // Universal link format (fallback)
      'https://rabby.io/wc?uri=${Uri.encodeComponent(wcUri)}',
    ];

    for (final deepLink in deepLinkFormats) {
      try {
        AppLogger.wallet('Trying deep link format', data: {
          'format': deepLink.substring(0, deepLink.length > 80 ? 80 : deepLink.length),
        });

        final uri = Uri.parse(deepLink);
        final canLaunch = await canLaunchUrl(uri);

        if (!canLaunch) {
          AppLogger.wallet('Cannot launch this URI format, trying next...');
          continue;
        }

        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          AppLogger.wallet('Successfully launched Rabby with deep link');
          return true;
        }
      } catch (e) {
        AppLogger.w('Deep link format failed: $e');
        continue;
      }
    }

    // All formats failed - try to open app store
    AppLogger.w('All deep link formats failed, opening app store');
    await _openAppStore();
    return false;
  }

  Future<void> _openAppStore() async {
    try {
      String storeUrl;
      if (Platform.isIOS) {
        storeUrl =
            'https://apps.apple.com/app/id${WalletConstants.rabbyAppStoreId}';
      } else if (Platform.isAndroid) {
        storeUrl =
            'https://play.google.com/store/apps/details?id=${WalletConstants.rabbyPackageAndroid}';
      } else {
        return;
      }

      AppLogger.wallet('Opening app store', data: {'url': storeUrl});
      final uri = Uri.parse(storeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening app store', e);
    }
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
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    AppLogger.wallet('RabbyWalletAdapter.connect() started', data: {
      'chainId': chainId,
    });

    // Initialize WalletConnect
    await initialize();

    // Check if already connected with valid session
    if (isConnected && connectedAddress != null) {
      AppLogger.wallet('Reusing existing session', data: {
        'address': connectedAddress,
      });

      final wallet = WalletEntity(
        address: connectedAddress!,
        type: walletType,
        chainId: requestedChainId ?? currentChainId,
        connectedAt: DateTime.now(),
      );
      return wallet;
    }

    // Set up connection tracking
    final completer = Completer<WalletEntity>();
    StreamSubscription? subscription;

    // Subscribe to connection stream
    subscription = connectionStream.listen(
      (status) {
        AppLogger.wallet('Connection status update', data: {
          'isConnected': status.isConnected,
          'hasError': status.hasError,
          'progressMessage': status.progressMessage,
        });

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
        AppLogger.e('Connection stream error', error);
        if (!completer.isCompleted) {
          completer.completeError(
            WalletException(
              message: 'Connection stream error: $error',
              code: 'STREAM_ERROR',
            ),
          );
        }
      },
    );

    try {
      // Start connection process in parent class (generates URI)
      AppLogger.wallet('Starting WalletConnect connection...');
      unawaited(super.connect(chainId: chainId, cluster: cluster));

      // Wait for URI to be generated with polling
      final uri = await _waitForUri();

      if (uri == null) {
        throw const WalletException(
          message: 'Failed to generate connection URI',
          code: 'URI_GENERATION_FAILED',
        );
      }

      // Open Rabby Wallet with the URI
      final launched = await openWithUri(uri);

      if (!launched) {
        AppLogger.w('Failed to open Rabby Wallet app');
        // Don't throw - user might scan QR code manually
      }

      // Wait for connection with timeout
      AppLogger.wallet('Waiting for wallet approval...');
      final wallet = await completer.future.timeout(
        AppConstants.connectionTimeout,
        onTimeout: () {
          throw const WalletException(
            message: 'Connection timed out. Please approve the connection in Rabby Wallet.',
            code: 'TIMEOUT',
          );
        },
      );

      AppLogger.wallet('Rabby connection successful', data: {
        'address': wallet.address,
        'chainId': wallet.chainId,
      });

      return wallet;
    } catch (e) {
      AppLogger.e('Rabby connection failed', e);
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }
}
