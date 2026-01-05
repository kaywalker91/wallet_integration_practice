import 'dart:async';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// MetaMask wallet adapter (extends WalletConnect with deep linking)
///
/// This adapter properly handles deep link callbacks to detect session
/// establishment when the user returns from MetaMask app.
class MetaMaskAdapter extends WalletConnectAdapter {
  MetaMaskAdapter({super.config});

  /// Flag to track if deep link handlers are registered
  bool _handlersRegistered = false;

  /// Flag to prevent duplicate callback processing
  bool _isProcessingCallback = false;

  /// Flag to track if deep link is being processed (for grace period logic)
  bool _deepLinkPending = false;

  @override
  WalletType get walletType => WalletType.metamask;

  /// Initialize the adapter and register deep link handlers
  @override
  Future<void> initialize() async {
    await super.initialize();

    _registerDeepLinkHandlers();
  }

  /// Register deep link handlers for MetaMask callbacks
  void _registerDeepLinkHandlers() {
    if (_handlersRegistered) return;

    final deepLinkService = DeepLinkService.instance;

    // Handler for MetaMask-specific paths (metamask host)
    deepLinkService.registerHandler('metamask', _handleMetaMaskCallback);

    // Handler for generic app resume (wip:// with no path)
    // This is called when wallet app returns without specific callback data
    deepLinkService.registerHandler('app_resumed', _handleAppResumed);

    _handlersRegistered = true;
    AppLogger.wallet('MetaMask deep link handlers registered');
  }

  /// Handle MetaMask-specific callback
  ///
  /// This is called when MetaMask sends a deep link callback after
  /// user approves the connection. We check for session establishment
  /// and clear the approval flag to prevent infinite loops.
  ///
  /// Improved flow:
  /// 1. Optimistic session check first (no delay)
  /// 2. If not connected, ensure relay is connected
  /// 3. Fall back to relay-based check with delay for propagation
  Future<void> _handleMetaMaskCallback(Uri uri) async {
    // Mark that deep link is being processed (for grace period logic)
    _deepLinkPending = true;

    // Guard: Skip if lifecycle callback is already checking session (race condition prevention)
    if (isCheckingSession) {
      AppLogger.wallet(
          'MetaMask callback: session check in progress by lifecycle, skipping');
      _deepLinkPending = false;
      return;
    }

    // Guard: Skip if already connected (prevents infinite loop)
    if (isConnected) {
      AppLogger.wallet('MetaMask callback ignored: already connected');
      _deepLinkPending = false;
      return;
    }

    // Guard: Skip if already processing a callback (prevent duplicate processing)
    if (_isProcessingCallback) {
      AppLogger.wallet('MetaMask callback ignored: already processing');
      _deepLinkPending = false;
      return;
    }

    _isProcessingCallback = true;

    // Reset background reconnection counter since we're now in foreground
    resetBackgroundReconnectionAttempts();

    try {
      AppLogger.wallet('MetaMask callback received', data: {
        'uri': uri.toString(),
        'isWaitingForApproval': isWaitingForApproval,
      });

      // Step 1: Optimistic session check (no delay)
      // This catches sessions that were already established
      await optimisticSessionCheck();
      if (isConnected) {
        AppLogger.wallet('MetaMask: Session found via optimistic check');
        return;
      }

      // Step 2: Ensure relay is connected before checking session
      // Relay may have disconnected while app was in background
      // Use 8s timeout to allow time for WebSocket reconnection after Android Doze
      final relayConnected = await ensureRelayConnected(
        timeout: const Duration(seconds: 8),
      );

      if (!relayConnected) {
        AppLogger.wallet(
            'MetaMask callback: relay reconnection failed, trying fallback');
        // Try aggressive reconnection as fallback
        await progressiveRelayReconnect();
      }

      // Step 3: Wait for session propagation via relay
      // This delay allows the relay to propagate the session approval
      await Future.delayed(const Duration(milliseconds: 300));

      // Step 4: Check for session again after relay stabilization
      await checkConnectionOnResume();

      if (isConnected) {
        AppLogger.wallet('MetaMask: Session found after relay check');
      } else {
        AppLogger.wallet(
            'MetaMask callback: no session found after relay check');
      }
    } catch (e) {
      AppLogger.e('MetaMask callback error', e);
    } finally {
      _isProcessingCallback = false;
      _deepLinkPending = false;
    }
  }

  /// Handle generic app resumed callback
  ///
  /// This is called when the app resumes without specific wallet callback.
  /// We check for session establishment in case the wallet approved but
  /// didn't send a specific callback.
  Future<void> _handleAppResumed(Uri uri) async {
    // Mark that deep link is being processed (for grace period logic)
    _deepLinkPending = true;

    // Guard: Skip if lifecycle callback is already checking session (race condition prevention)
    if (isCheckingSession) {
      AppLogger.wallet(
          'App resumed: session check in progress by lifecycle, skipping');
      _deepLinkPending = false;
      return;
    }

    // Guard: Skip if already connected (prevents infinite loop)
    if (isConnected) {
      AppLogger.wallet('App resumed callback ignored: already connected');
      _deepLinkPending = false;
      return;
    }

    // Guard: Skip if already processing a callback
    if (_isProcessingCallback) {
      AppLogger.wallet('App resumed callback ignored: already processing');
      _deepLinkPending = false;
      return;
    }

    _isProcessingCallback = true;

    // Reset background reconnection counter since we're now in foreground
    resetBackgroundReconnectionAttempts();

    try {
      AppLogger.wallet('App resumed callback (MetaMask adapter)', data: {
        'isWaitingForApproval': isWaitingForApproval,
      });

      // Only process if we're waiting for approval
      if (!isWaitingForApproval) {
        AppLogger.wallet(
            'App resumed: not waiting for approval, skipping session check');
        return;
      }

      // Step 1: Optimistic session check
      await optimisticSessionCheck();
      if (isConnected) {
        AppLogger.wallet('MetaMask: Session found via app resume optimistic check');
        return;
      }

      // Step 2: Ensure relay is connected
      // Use 8s timeout to allow time for WebSocket reconnection after Android Doze
      await ensureRelayConnected(timeout: const Duration(seconds: 8));

      // Step 3: Wait for propagation and check again
      await Future.delayed(const Duration(milliseconds: 200));
      await checkConnectionOnResume();

      if (isConnected) {
        AppLogger.wallet('MetaMask: Session found after app resume relay check');
      }
    } catch (e) {
      AppLogger.e('App resumed callback error (MetaMask)', e);
    } finally {
      _isProcessingCallback = false;
      _deepLinkPending = false;
    }
  }

  /// Check if a deep link is currently being processed
  bool get isDeepLinkPending => _deepLinkPending;

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
  bool validateWalletSpecific(SessionData session) {
    final name = session.peer.metadata.name.toLowerCase();
    final redirect =
        session.peer.metadata.redirect?.native?.toLowerCase() ?? '';

    // Accept if MetaMask identified
    if (name.contains('metamask')) {
      AppLogger.wallet('MetaMask session accepted: peer name contains metamask',
          data: {'peerName': name});
      return true;
    }

    if (redirect.contains('metamask://') || redirect.contains('metamask:')) {
      AppLogger.wallet(
          'MetaMask session accepted: redirect contains metamask scheme',
          data: {'redirect': redirect});
      return true;
    }

    // Explicitly reject sessions from other known wallets
    // This prevents session confusion when multiple wallets are installed
    final otherWallets = [
      'trust',
      'okx',
      'okex',
      'phantom',
      'rabby',
      'coinbase',
      'rainbow',
      'zerion',
      'argent',
    ];

    for (final wallet in otherWallets) {
      if (name.contains(wallet)) {
        AppLogger.wallet('MetaMask session REJECTED: belongs to $wallet',
            data: {'peerName': name, 'wallet': wallet});
        return false;
      }
    }

    // Reject unknown sessions (stricter validation)
    AppLogger.d('MetaMaskAdapter ignored session for unknown wallet: $name');
    return false;
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

  @override
  Future<void> dispose() async {
    // Unregister deep link handlers
    if (_handlersRegistered) {
      final deepLinkService = DeepLinkService.instance;
      deepLinkService.unregisterHandler('metamask');
      deepLinkService.unregisterHandler('app_resumed');
      _handlersRegistered = false;
      AppLogger.wallet('MetaMask deep link handlers unregistered');
    }

    // Reset state flags
    _isProcessingCallback = false;
    _deepLinkPending = false;

    await super.dispose();
  }
}
