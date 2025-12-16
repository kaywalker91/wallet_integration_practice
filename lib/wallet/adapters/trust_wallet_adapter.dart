import 'dart:async';
import 'dart:io';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Trust Wallet adapter (extends WalletConnect with deep linking)
///
/// Implements deep link handlers to detect when user returns from Trust Wallet
/// after approving the connection. This is critical for handling the case where
/// the app is backgrounded during approval and the relay WebSocket disconnects.
///
/// Inherits lifecycle observer from [WalletConnectAdapter] to detect app resume
/// and proactively check for session updates when returning from wallet app.
class TrustWalletAdapter extends WalletConnectAdapter {
  TrustWalletAdapter({super.config});

  /// Flag to track if deep link handlers have been registered
  bool _handlersRegistered = false;

  /// Flag to prevent duplicate callback processing
  /// This prevents issues when multiple callbacks arrive in quick succession
  bool _isProcessingCallback = false;

  @override
  WalletType get walletType => WalletType.trustWallet;

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Register Trust Wallet-specific deep link handlers
    _registerDeepLinkHandlers();
  }

  /// Register deep link handlers for Trust Wallet callbacks
  ///
  /// These handlers are triggered when:
  /// 1. User returns from Trust Wallet app after approving connection
  /// 2. Trust Wallet app sends callback to our app via deep link
  ///
  /// The handlers proactively check for session establishment
  /// to reduce the wait time for connection completion.
  void _registerDeepLinkHandlers() {
    if (_handlersRegistered) return;

    final deepLinkService = DeepLinkService.instance;

    // Handler for Trust Wallet-specific paths (trust, trustwallet hosts)
    deepLinkService.registerHandler('trust', _handleTrustCallback);
    deepLinkService.registerHandler('trustwallet', _handleTrustCallback);

    // Note: We do NOT register 'app_resumed' handler here to avoid
    // conflict with OKX Wallet adapter which also uses this handler.
    // The lifecycle observer in WalletConnectAdapter base class
    // will handle generic app resume scenarios.

    _handlersRegistered = true;
    AppLogger.wallet('Trust Wallet deep link handlers registered');
  }

  /// Handle Trust Wallet-specific callback
  ///
  /// This is called when Trust Wallet sends a deep link callback after
  /// user approves the connection. We check for session establishment
  /// and clear the approval flag to prevent infinite loops.
  Future<void> _handleTrustCallback(Uri uri) async {
    // Guard: Skip if already connected (prevents infinite loop)
    if (isConnected) {
      AppLogger.wallet('Trust callback ignored: already connected');
      return;
    }

    // Guard: Skip if already processing a callback (prevent duplicate processing)
    if (_isProcessingCallback) {
      AppLogger.wallet('Trust callback ignored: already processing');
      return;
    }

    _isProcessingCallback = true;

    try {
      AppLogger.wallet('Trust Wallet callback received', data: {
        'uri': uri.toString(),
        'isWaitingForApproval': isWaitingForApproval,
      });

      // CRITICAL: Delay to allow relay server to propagate session
      // Trust Wallet may send callback before session is fully synced
      // This matches the pattern used in OKX Wallet adapter
      await Future.delayed(const Duration(milliseconds: 200));

      // Directly call the protected method instead of lifecycle callback
      // This prevents duplicate triggers from lifecycle events
      await checkConnectionOnResume();
    } finally {
      _isProcessingCallback = false;
    }
  }

  @override
  Future<void> dispose() async {
    // Unregister deep link handlers
    if (_handlersRegistered) {
      final deepLinkService = DeepLinkService.instance;
      deepLinkService.unregisterHandler('trust');
      deepLinkService.unregisterHandler('trustwallet');
      _handlersRegistered = false;
      AppLogger.wallet('Trust Wallet deep link handlers unregistered');
    }

    await super.dispose();
  }

  /// Validate session - only accept Trust Wallet sessions
  ///
  /// This prevents cross-wallet session conflicts (e.g., OKX session being reused).
  ///
  /// Validation strategy:
  /// 1. Accept if name contains 'trust'
  /// 2. Accept if redirect contains 'trust://' scheme
  /// 3. Reject if name clearly belongs to another wallet
  /// 4. Accept unknown/empty names (benefit of the doubt for new sessions)
  @override
  bool isSessionValid(SessionData session) {
    final peer = session.peer;
    final name = peer.metadata.name.toLowerCase();
    final redirect = peer.metadata.redirect?.native?.toLowerCase() ?? '';

    AppLogger.wallet('Trust session validation check', data: {
      'peerName': name,
      'redirect': redirect,
    });

    // Accept if clearly Trust Wallet
    if (name.contains('trust')) {
      AppLogger.wallet('Session ACCEPTED: Trust name match');
      return true;
    }

    // Accept if redirect contains trust scheme
    if (redirect.contains('trust://') || redirect.contains('trustwallet')) {
      AppLogger.wallet('Session ACCEPTED: Trust redirect match', data: {
        'redirect': redirect,
      });
      return true;
    }

    // Reject if clearly another wallet
    final otherWallets = ['metamask', 'okx', 'okex', 'phantom', 'rabby', 'rainbow', 'coinbase'];
    for (final wallet in otherWallets) {
      if (name.contains(wallet)) {
        AppLogger.wallet('Session REJECTED: belongs to $wallet');
        return false;
      }
    }

    // Accept unknown sessions (may be Trust Wallet with different metadata)
    if (name.isEmpty) {
      AppLogger.wallet('Session ACCEPTED: empty name (new session)');
      return true;
    }

    // Default: accept unknown wallet names (benefit of the doubt)
    AppLogger.wallet('Session ACCEPTED: unknown wallet "$name" (benefit of doubt)');
    return true;
  }

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
