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
  ///
  /// CRITICAL: Trust Wallet uses WalletConnect relay for session data,
  /// not deep link parameters. If the relay WebSocket disconnected while
  /// we were in background, we must reconnect before checking for session.
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
        'isRelayConnected': isRelayConnected,
      });

      // CRITICAL: Ensure relay is connected before checking session
      // Trust Wallet sends session approval via relay server, not deep link
      // The relay may have disconnected while app was in background
      final relayReady = await ensureRelayConnected(
        timeout: const Duration(seconds: 3),
      );

      AppLogger.wallet('Trust callback: Relay reconnection result', data: {
        'relayReady': relayReady,
      });

      // Increased delay to allow relay server to propagate session
      // Trust Wallet may send callback before session is fully synced
      // 500ms provides more buffer than the original 200ms
      await Future.delayed(const Duration(milliseconds: 500));

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

      AppLogger.wallet('Launching Trust Wallet deep link', data: {
        'rawUri': wcUri.substring(0, wcUri.length.clamp(0, 50)),
        'transformedUri': deepLink.substring(0, deepLink.length.clamp(0, 80)),
      });

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
    // Ensure adapter is initialized
    await initialize();

    // Register deep link handlers for callback
    _registerDeepLinkHandlers();

    // CRITICAL: Clear any previous WalletConnect sessions/pairings before connecting.
    // This prevents issues where stale session data from a previous wallet (e.g., Phantom)
    // could interfere with the Trust Wallet connection or cause phantom.com redirects.
    AppLogger.wallet('Trust Wallet: clearing previous sessions before connect');
    await clearPreviousSessions();

    try {
      // Step 1: Prepare connection (generates URI without blocking on approval)
      final sessionFuture = await prepareConnection(chainId: chainId);

      // Step 2: Get the generated URI
      final uri = await getConnectionUri();
      if (uri == null) {
        throw const WalletException(
          message: 'Failed to generate WalletConnect URI for Trust Wallet',
          code: 'URI_GENERATION_FAILED',
        );
      }

      AppLogger.wallet('Trust Wallet: WC URI generated, opening wallet app', data: {
        'wcUri': uri.substring(0, uri.length.clamp(0, 50)),
      });

      // Step 3: Open Trust Wallet with the URI (trust://wc?uri=...)
      await openWithUri(uri);

      // Step 4: Wait for session approval with timeout
      final wallet = await sessionFuture.timeout(
        AppConstants.connectionTimeout,
        onTimeout: () {
          throw const WalletException(
            message: 'Connection timed out waiting for Trust Wallet approval',
            code: 'TIMEOUT',
          );
        },
      );

      // Return wallet with correct type
      return wallet.copyWith(type: walletType);
    } catch (e) {
      AppLogger.e('Trust Wallet connection error', e);
      rethrow;
    }
  }
}
