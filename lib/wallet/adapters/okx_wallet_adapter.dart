import 'dart:async' show Completer, StreamSubscription, unawaited;
import 'dart:io';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// OKX Wallet adapter (extends WalletConnect with deep linking)
///
/// OKX Wallet (com.okx.wallet) is a multi-chain wallet supporting EVM and Solana.
/// This adapter handles session validation to prevent cross-wallet session conflicts
/// and implements deep linking for native app launch.
class OkxWalletAdapter extends WalletConnectAdapter {
  OkxWalletAdapter({super.config});

  @override
  WalletType get walletType => WalletType.okxWallet;

  /// Check if OKX Wallet is installed
  Future<bool> isOkxInstalled() async {
    try {
      final uri = Uri.parse(WalletConstants.okxWalletDeepLink);
      final canLaunch = await canLaunchUrl(uri);
      AppLogger.wallet('OKX Wallet installed check', data: {'installed': canLaunch});
      return canLaunch;
    } catch (e) {
      AppLogger.e('Error checking OKX Wallet installation', e);
      return false;
    }
  }

  /// Open OKX Wallet app
  Future<bool> openOkx() async {
    try {
      final uri = Uri.parse(WalletConstants.okxWalletDeepLink);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening OKX Wallet', e);
      return false;
    }
  }

  /// Open OKX Wallet with WalletConnect URI
  ///
  /// Uses the correct deep link format for OKX Wallet (com.okx.wallet):
  /// - Custom Scheme: okxwallet://wc?uri=...
  /// - Universal Link: https://web3.okx.com/download?uri=...
  ///
  /// Note: 'okxwallet://' is different from 'okx://' (exchange app)
  Future<bool> openWithUri(String wcUri) async {
    AppLogger.wallet('Attempting to open OKX Wallet with WC URI', data: {
      'uriLength': wcUri.length,
      'uriPrefix': wcUri.substring(0, wcUri.length > 50 ? 50 : wcUri.length),
    });

    final encodedUri = Uri.encodeComponent(wcUri);

    // 1. Try Custom Scheme: okxwallet://wc?uri=...
    // Note: 'okxwallet' (not 'okx') - OKX Wallet app specific scheme
    // Registered in WalletConnect Explorer for com.okx.wallet
    final schemeUrl = 'okxwallet://wc?uri=$encodedUri';

    try {
      final schemeUri = Uri.parse(schemeUrl);

      final launchedScheme = await launchUrl(
        schemeUri,
        mode: LaunchMode.externalApplication,
      );

      if (launchedScheme) {
        AppLogger.wallet('Successfully launched OKX Wallet Custom Scheme');
        return true;
      }
    } catch (e) {
      AppLogger.w('OKX Wallet Custom Scheme failed: $e');
    }

    // 2. Try Universal Link: https://web3.okx.com/download?uri=...
    // Note: web3.okx.com (not www.okx.com) - OKX Wallet specific domain
    final universalUrl = 'https://web3.okx.com/download?uri=$encodedUri';

    try {
      final universalUri = Uri.parse(universalUrl);
      final launchedUniversal = await launchUrl(
        universalUri,
        mode: LaunchMode.externalApplication,
      );

      if (launchedUniversal) {
        AppLogger.wallet('Successfully launched OKX Wallet Universal Link');
        return true;
      }
    } catch (e) {
      AppLogger.w('OKX Wallet Universal Link failed: $e');
    }

    // 3. Fallback to raw wc: URI (OS picker)
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

    // All formats failed
    AppLogger.w('All OKX Wallet deep link formats failed');
    throw WalletNotInstalledException(
      walletType: walletType.name,
      message: 'OKX Wallet is not installed',
    );
  }

  Future<void> _openAppStore() async {
    try {
      String storeUrl;
      if (Platform.isIOS) {
        storeUrl =
            'https://apps.apple.com/app/id${WalletConstants.okxWalletAppStoreId}';
      } else if (Platform.isAndroid) {
        storeUrl =
            'https://play.google.com/store/apps/details?id=${WalletConstants.okxWalletPackageAndroid}';
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

  /// Validate session - only accept OKX Wallet sessions
  /// This prevents cross-wallet session conflicts (e.g., Trust Wallet session being reused)
  @override
  bool isSessionValid(SessionData session) {
    final name = session.peer?.metadata.name.toLowerCase() ?? '';
    final isValid = name.contains('okx') || name.contains('okex');
    if (!isValid) {
      AppLogger.d('OkxWalletAdapter ignored session for: $name');
    }
    return isValid;
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    AppLogger.wallet('OkxWalletAdapter.connect() started', data: {
      'chainId': chainId,
    });

    // Initialize WalletConnect
    await initialize();

    // Check if already connected with valid session
    if (isConnected && connectedAddress != null) {
      AppLogger.wallet('Reusing existing OKX session', data: {
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

      // Open OKX Wallet with the URI
      // Throws WalletNotInstalledException if app is not installed
      await openWithUri(uri);

      // Wait for connection with timeout
      AppLogger.wallet('Waiting for wallet approval...');
      final wallet = await completer.future.timeout(
        AppConstants.connectionTimeout,
        onTimeout: () {
          throw const WalletException(
            message: 'Connection timed out. Please approve the connection in OKX Wallet.',
            code: 'TIMEOUT',
          );
        },
      );

      AppLogger.wallet('OKX Wallet connection successful', data: {
        'address': wallet.address,
        'chainId': wallet.chainId,
      });

      return wallet;
    } catch (e) {
      AppLogger.e('OKX Wallet connection failed', e);
      rethrow;
    } finally {
      await subscription.cancel();
    }
  }
}
