import 'dart:async' show Completer, StreamSubscription, unawaited;
import 'package:reown_appkit/reown_appkit.dart';
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
  ///
  /// Strategy order (optimized for mobile-to-mobile connection):
  ///
  /// 1. rabby://walletconnect?uri=... - Alternative path
  /// 2. rabby://connect?uri=... - Connect path
  /// 3. rabby://wc?uri=... - Standard WC path
  /// 4. rabby://?uri=... - No path
  /// 5. https://rabby.io/wc?uri=... - Universal Link
  /// 6. wc:// scheme - OS wallet picker (kept late to avoid hijacking)
  /// 7. raw wc: URI - Last resort
  Future<bool> openWithUri(String wcUri) async {
    AppLogger.wallet('Attempting to open Rabby with WC URI', data: {
      'uriLength': wcUri.length,
      'uriPrefix': wcUri.substring(0, wcUri.length > 50 ? 50 : wcUri.length),
    });

    // URL encode the URI for safe passing as a query parameter
    final encodedUri = Uri.encodeComponent(wcUri);

    // Strategy 1: Alternative path (rabby://walletconnect?uri=...)
    try {
      final altPathUrl = 'rabby://walletconnect?uri=$encodedUri';
      final uri = Uri.parse(altPathUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched Rabby with walletconnect path');
        return true;
      }
    } catch (e) {
      AppLogger.w('Rabby walletconnect path failed: $e');
    }

    // Strategy 2: Connect path (rabby://connect?uri=...)
    try {
      final connectUrl = 'rabby://connect?uri=$encodedUri';
      final uri = Uri.parse(connectUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched Rabby with connect path');
        return true;
      }
    } catch (e) {
      AppLogger.w('Rabby connect path failed: $e');
    }

    // Strategy 3: Standard WC path (rabby://wc?uri=...)
    final schemeUrl = 'rabby://wc?uri=$encodedUri';
    try {
      final schemeUri = Uri.parse(schemeUrl);
      final launchedScheme = await launchUrl(
        schemeUri,
        mode: LaunchMode.externalApplication,
      );

      if (launchedScheme) {
        AppLogger.wallet('Successfully launched Rabby Custom Scheme (wc path)');
        return true;
      }
    } catch (e) {
      AppLogger.w('Rabby Custom Scheme (wc path) failed: $e');
    }

    // Strategy 4: No path, query param only (rabby://?uri=...)
    try {
      final noPathUrl = 'rabby://?uri=$encodedUri';
      final uri = Uri.parse(noPathUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched Rabby with no-path scheme');
        return true;
      }
    } catch (e) {
      AppLogger.w('Rabby no-path scheme failed: $e');
    }

    // Strategy 5: Universal Link (https://rabby.io/wc?uri=...)
    final universalUrl = 'https://rabby.io/wc?uri=$encodedUri';
    try {
      final universalUri = Uri.parse(universalUrl);
      final launchedUniversal = await launchUrl(
        universalUri,
        mode: LaunchMode.externalApplication,
      );

      if (launchedUniversal) {
        AppLogger.wallet('Successfully launched Rabby Universal Link');
        return true;
      }
    } catch (e) {
      AppLogger.w('Rabby Universal Link failed: $e');
    }

    // Strategy 6: wc:// scheme (OS wallet picker)
    // Moved to bottom to reduce hijacking by other wallets.
    try {
      final wcSchemeUri = wcUri.replaceFirst('wc:', 'wc://');
      final uri = Uri.parse(wcSchemeUri);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('Successfully launched via wc:// scheme (OS wallet picker)');
        return true;
      }
    } catch (e) {
      AppLogger.w('wc:// scheme launch failed: $e');
    }

    // Strategy 7: Raw wc: URI (last resort)
    try {
      final rawUri = Uri.parse(wcUri);
      final launchedRaw = await launchUrl(
        rawUri,
        mode: LaunchMode.externalApplication,
      );
      if (launchedRaw) {
        AppLogger.wallet('Launched raw WC URI');
        return true;
      }
    } catch (e) {
      AppLogger.w('Raw WC URI launch failed: $e');
    }

    // All strategies failed
    AppLogger.w('All Rabby deep link strategies failed');
    throw WalletNotInstalledException(
      walletType: walletType.name,
      message: 'Rabby Wallet is not installed or does not support deep linking',
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
    final isValid = name.contains('rabby');
    if (!isValid) {
      AppLogger.d('RabbyWalletAdapter ignored session for: $name');
    }
    return isValid;
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
      // Throws WalletNotInstalledException if app is not installed
      await openWithUri(uri);

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
