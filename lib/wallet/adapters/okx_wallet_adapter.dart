import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Deep link strategy result for diagnostic tracking
class _DeepLinkResult {
  const _DeepLinkResult({
    required this.strategyName,
    required this.uri,
    required this.launched,
    this.error,
  });

  final String strategyName;
  final String uri;
  final bool launched;
  final String? error;
}

/// OKX Wallet adapter (extends WalletConnect with deep linking)
///
/// OKX Wallet (com.okx.wallet) is a multi-chain wallet supporting EVM and Solana.
/// This adapter handles session validation to prevent cross-wallet session conflicts
/// and implements deep linking for native app launch.
///
/// Inherits lifecycle observer from [WalletConnectAdapter] to detect app resume
/// and proactively check for session updates when returning from wallet app.
class OkxWalletAdapter extends WalletConnectAdapter {
  OkxWalletAdapter({super.config});

  /// Flag to track if deep link handlers have been registered
  bool _handlersRegistered = false;

  /// Flag to prevent duplicate callback processing
  /// This prevents the infinite loop when multiple callbacks arrive
  bool _isProcessingCallback = false;

  /// Flag indicating deep link is currently being processed
  /// Used for grace period during timeout to wait for deep link arrival
  bool _deepLinkPending = false;

  /// Flag indicating we're in post-timeout recovery mode
  /// When true, we should still try to recover session on resume
  bool _pendingPostTimeoutRecovery = false;

  @override
  WalletType get walletType => WalletType.okxWallet;

  /// Override lifecycle to handle post-error recovery for OKX
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Additional OKX-specific handling: post-timeout recovery
    if (state == AppLifecycleState.resumed && _pendingPostTimeoutRecovery) {
      AppLogger.wallet('OKX: Post-timeout recovery on resume');
      unawaited(_checkForPostErrorRecovery());
    }
  }

  /// Check for session recovery after soft timeout
  /// This runs when user returns from OKX after a soft timeout occurred
  Future<void> _checkForPostErrorRecovery() async {
    if (isConnected) {
      AppLogger.wallet('OKX post-error: Already connected');
      _pendingPostTimeoutRecovery = false;
      return;
    }

    AppLogger.wallet('=== OKX Post-Error Recovery START ===');

    // Wait for relay to reconnect (now in foreground)
    final relayOk = await ensureRelayConnected(
      timeout: const Duration(seconds: 8),
    );
    AppLogger.wallet('Post-error relay reconnection', data: {'success': relayOk});

    // Small delay for session sync
    await Future.delayed(const Duration(milliseconds: 500));

    // Check for session
    await optimisticSessionCheck();

    if (isConnected && connectedAddress != null) {
      AppLogger.wallet('=== OKX Post-Error Recovery SUCCESS ===');
      _pendingPostTimeoutRecovery = false;
      // Connection status will be emitted by optimisticSessionCheck
    } else {
      AppLogger.wallet('=== OKX Post-Error Recovery: No session ===');
      // Keep _pendingPostTimeoutRecovery for next resume attempt (limited)
    }
  }

  @override
  Future<void> initialize() async {
    await super.initialize();

    // Register OKX-specific deep link handlers
    _registerDeepLinkHandlers();
  }

  /// Register deep link handlers for OKX wallet callbacks
  ///
  /// These handlers are triggered when:
  /// 1. User returns from OKX app after approving connection
  /// 2. OKX app sends callback to our app via deep link
  ///
  /// The handlers proactively check for session establishment
  /// to reduce the wait time for connection completion.
  void _registerDeepLinkHandlers() {
    if (_handlersRegistered) return;

    final deepLinkService = DeepLinkService.instance;

    // Handler for OKX-specific paths (okx, okxwallet hosts)
    deepLinkService.registerHandler('okx', _handleOkxCallback);
    deepLinkService.registerHandler('okxwallet', _handleOkxCallback);

    // Handler for generic app resume (wip:// with no path)
    // This is called when wallet app returns without specific callback data
    deepLinkService.registerHandler('app_resumed', _handleAppResumed);

    _handlersRegistered = true;
    AppLogger.wallet('OKX deep link handlers registered');
  }

  /// Handle OKX-specific callback
  ///
  /// This is called when OKX Wallet sends a deep link callback after
  /// user approves the connection. We check for session establishment
  /// and clear the approval flag to prevent infinite loops.
  ///
  /// Improved flow:
  /// 1. Optimistic session check first (no delay)
  /// 2. If not connected, fall back to relay-based check
  Future<void> _handleOkxCallback(Uri uri) async {
    // Mark that deep link is being processed (for grace period logic)
    _deepLinkPending = true;

    // Guard: Skip if lifecycle callback is already checking session (race condition prevention)
    if (isCheckingSession) {
      AppLogger.wallet(
          'OKX callback: session check in progress by lifecycle, skipping');
      _deepLinkPending = false;
      return;
    }

    // Guard: Skip if already connected (prevents infinite loop)
    if (isConnected) {
      AppLogger.wallet('OKX callback ignored: already connected');
      _deepLinkPending = false;
      return;
    }

    // Guard: Skip if already processing a callback (prevent duplicate processing)
    if (_isProcessingCallback) {
      AppLogger.wallet('OKX callback ignored: already processing');
      _deepLinkPending = false;
      return;
    }

    _isProcessingCallback = true;

    try {
      AppLogger.wallet('OKX callback received', data: {
        'uri': uri.toString(),
        'isWaitingForApproval': isWaitingForApproval,
      });

      // OPTIMIZATION: Try optimistic session check first (no delay)
      // This can detect session immediately if it was already stored
      await optimisticSessionCheck();

      // If connected via optimistic check, we're done
      if (isConnected) {
        AppLogger.wallet('✅ OKX callback: connected via optimistic check');
        return;
      }

      // Fall back to relay-based check with delay
      await Future.delayed(const Duration(milliseconds: 200));

      // Directly call the protected method instead of lifecycle callback
      // This prevents duplicate triggers from lifecycle events
      await checkConnectionOnResume();
    } finally {
      _isProcessingCallback = false;
      _deepLinkPending = false;
    }
  }

  /// Handle generic app resume callback
  ///
  /// This is called when the app returns from background without
  /// specific callback data from OKX Wallet.
  ///
  /// Improved flow:
  /// 1. Optimistic session check first (no delay)
  /// 2. If not connected, fall back to relay-based check
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

    try {
      AppLogger.wallet('App resumed callback (OKX adapter)', data: {
        'isWaitingForApproval': isWaitingForApproval,
      });

      // OPTIMIZATION: Try optimistic session check first (no delay)
      await optimisticSessionCheck();

      // If connected via optimistic check, we're done
      if (isConnected) {
        AppLogger.wallet('✅ App resumed: connected via optimistic check');
        return;
      }

      // For new connections, use extended grace period since relay may need more time
      // to propagate the session. For session restoration, use shorter delay.
      if (isNewConnection) {
        AppLogger.wallet(
            'Empty callback during new connection - extended grace period');
        await Future.delayed(const Duration(milliseconds: 1200));

        // If still not connected after extended delay, delegate to connect() timeout
        // rather than triggering multiple retries that cause race conditions
        if (!isConnected) {
          AppLogger.wallet(
              'Session not yet established, delegating to connect timeout');
          return;
        }
      } else {
        // Fall back to relay-based check with delay (session restoration)
        await Future.delayed(const Duration(milliseconds: 300));

        // Directly call the protected method instead of lifecycle callback
        await checkConnectionOnResume();
      }
    } finally {
      _isProcessingCallback = false;
      _deepLinkPending = false;
    }
  }

  @override
  Future<void> dispose() async {
    // Unregister deep link handlers
    if (_handlersRegistered) {
      final deepLinkService = DeepLinkService.instance;
      deepLinkService.unregisterHandler('okx');
      deepLinkService.unregisterHandler('okxwallet');
      deepLinkService.unregisterHandler('app_resumed');
      _handlersRegistered = false;
      AppLogger.wallet('OKX deep link handlers unregistered');
    }

    await super.dispose();
  }

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

  /// Check which OKX app variants are installed
  ///
  /// OKX has two separate apps:
  /// - OKX Wallet (com.okx.wallet) -> okxwallet:// scheme
  /// - OKX Exchange (com.okinc.okex) -> okx:// scheme
  ///
  /// Returns a record with installation status for each app.
  /// This is used to prioritize the correct deep link scheme.
  Future<({bool walletInstalled, bool exchangeInstalled})> _checkOkxAppsInstalled() async {
    try {
      final walletUri = Uri.parse('${WalletConstants.okxWalletDeepLink}test');
      final exchangeUri = Uri.parse('okx://test');

      final walletInstalled = await canLaunchUrl(walletUri);
      final exchangeInstalled = await canLaunchUrl(exchangeUri);

      AppLogger.wallet('OKX app installation check', data: {
        'okxWalletInstalled': walletInstalled,
        'okxExchangeInstalled': exchangeInstalled,
        'platform': Platform.operatingSystem,
      });

      return (walletInstalled: walletInstalled, exchangeInstalled: exchangeInstalled);
    } catch (e) {
      AppLogger.e('Error checking OKX app installation', e);
      return (walletInstalled: false, exchangeInstalled: false);
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
  /// Uses intelligent platform-aware strategy selection:
  ///
  /// **Android Priority Order** (wc: scheme works better on Android):
  /// 0. Raw wc: URI (Android OS passes data directly to registered wallet)
  /// 0b. wc:// universal scheme
  /// Then fallback to OKX-specific schemes if wc: fails...
  ///
  /// **iOS Priority Order** (OKX-specific schemes first):
  /// 1. okxwallet://wc?uri= encoded (Primary OKX Wallet scheme)
  /// 2. okxwallet://wc?uri= non-encoded (Uri constructor variant)
  /// 3. okx://wc?uri= (Exchange app WC scheme - if exchange installed)
  /// 4. okx://wallet/dapp/wc?uri= (DApp browser path)
  /// 5. Universal Link with deeplink (double-encoded)
  /// 6. Universal Link with uri (single-encoded)
  /// 7-8. wc:// and wc: schemes (LAST RESORT on iOS - may open wrong wallet)
  ///
  /// Note: OKX has two apps with different schemes:
  /// - OKX Wallet (com.okx.wallet) -> 'okxwallet://'
  /// - OKX Exchange (com.okinc.okex) -> 'okx://'
  ///
  /// **Why wc: first on Android?**
  /// OKX-specific schemes (okxwallet://wc?uri=...) fail to parse URI parameter
  /// on Android, causing app to open without session proposal. The standard
  /// wc: scheme allows Android OS to pass data directly to registered apps.
  Future<bool> openWithUri(String wcUri) async {
    AppLogger.wallet('=== OKX Wallet openWithUri() START ===');
    _logUriDetails(wcUri);

    // Step 1: Check which OKX apps are installed
    final (:walletInstalled, :exchangeInstalled) = await _checkOkxAppsInstalled();

    // Early validation: warn if no OKX app detected
    if (!walletInstalled && !exchangeInstalled) {
      AppLogger.wallet('⚠️ WARNING: No OKX app detected, will try universal links');
    }

    // Prepare encoded versions
    final encodedUri = Uri.encodeComponent(wcUri);
    final doubleEncodedDeepLink = _buildDoubleEncodedDeepLink(wcUri);

    AppLogger.wallet('Encoding summary', data: {
      'originalLength': wcUri.length,
      'encodedLength': encodedUri.length,
      'doubleEncodedLength': doubleEncodedDeepLink.length,
      'walletInstalled': walletInstalled,
      'exchangeInstalled': exchangeInstalled,
    });

    // Track all attempts for diagnostic purposes
    final List<_DeepLinkResult> attempts = [];

    // === ANDROID PRIORITY: Standard wc: scheme ===
    // On Android, the standard wc: scheme works better than OKX-specific schemes
    // because Android OS handles the data passing directly to registered apps.
    // OKX-specific schemes (okxwallet://wc?uri=...) fail to parse URI parameter on Android.
    if (Platform.isAndroid) {
      AppLogger.wallet('🤖 Android detected: Trying standard wc: scheme FIRST');

      // Strategy 0 (Android Priority): Raw wc: URI
      // Android OS passes the entire URI data directly to the registered wallet app
      var result = await _tryStrategy7RawWcUri(wcUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 0 (Android Priority): Raw wc: URI SUCCESS');
        return true;
      }

      // Strategy 0b: wc:// universal scheme
      result = await _tryStrategyWcUniversalScheme(wcUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 0b (Android): wc:// universal scheme SUCCESS');
        return true;
      }

      AppLogger.wallet('⚠️ Android wc: strategies failed, falling back to OKX-specific schemes');
    }

    // === OKX Wallet specific strategies (PRIORITY for iOS) ===
    // Try OKX Wallet schemes first if installed
    if (walletInstalled) {
      // Strategy 1: okxwallet://wc?uri= (Encoded) - PRIMARY
      var result = await _tryStrategy2EncodedUri(encodedUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 1 SUCCESS: okxwallet://wc?uri= encoded');
        return true;
      }

      // Strategy 2: okxwallet://wc?uri= (Non-encoded, Uri constructor)
      result = await _tryStrategy1NonEncodedUri(wcUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 2 SUCCESS: okxwallet://wc?uri= non-encoded');
        return true;
      }
    }

    // === OKX Exchange app strategies ===
    // Fallback to Exchange app if Wallet not installed
    if (exchangeInstalled) {
      // Strategy 3: okx://wc?uri= (Exchange app WC scheme)
      var result = await _tryStrategy3ExchangeAppScheme(encodedUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 3 SUCCESS: okx://wc?uri=');
        return true;
      }

      // Strategy 4: okx://wallet/dapp/wc?uri= (DApp browser path)
      result = await _tryStrategy4DappBrowser(wcUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 4 SUCCESS: okx://wallet/dapp/wc');
        return true;
      }
    }

    // === Universal Link strategies ===
    // Works even without app installed, may redirect to app store

    // Strategy 5: Universal Link with deeplink (double-encoded)
    var result = await _tryStrategy5UniversalLinkDeeplink(doubleEncodedDeepLink);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Strategy 5 SUCCESS: Universal Link double-encoded');
      return true;
    }

    // Strategy 6: Universal Link with uri (single-encoded)
    result = await _tryStrategy6UniversalLinkUri(encodedUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Strategy 6 SUCCESS: Universal Link single-encoded');
      return true;
    }

    // === LAST RESORT strategies (iOS only) ===
    // On Android, wc: schemes are tried FIRST (see above)
    // On iOS, only try wc: schemes if no OKX-specific app was detected
    // WARNING: wc:// scheme may open wrong wallet!
    if (Platform.isIOS && !walletInstalled && !exchangeInstalled) {
      AppLogger.wallet('⚠️ WARNING: iOS fallback - Trying wc:// scheme - may open wrong wallet');

      // Strategy 7: wc:// universal scheme (RISKY)
      result = await _tryStrategyWcUniversalScheme(wcUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 7 (iOS RISKY): wc:// universal scheme');
        return true;
      }

      // Strategy 8: Raw wc: URI (OS picker)
      result = await _tryStrategy7RawWcUri(wcUri);
      attempts.add(result);
      if (result.launched) {
        AppLogger.wallet('🎯 Strategy 8 (iOS RISKY): Raw wc: URI');
        return true;
      }
    }

    // All strategies failed - log comprehensive diagnostic
    _logAllFailedAttempts(attempts);

    throw WalletNotInstalledException(
      walletType: walletType.name,
      message: 'OKX Wallet is not installed or failed to process WC URI. '
          'Tried ${attempts.length} strategies. '
          'walletInstalled=$walletInstalled, exchangeInstalled=$exchangeInstalled',
    );
  }

  /// Strategy: wc:// universal scheme
  ///
  /// Per WalletConnect v2 docs, wallets should register "wc://" to handle
  /// WalletConnect pairing URIs. This triggers the OS wallet picker if
  /// multiple wallets support it, or directly opens the registered wallet.
  ///
  /// Format: wc://{pairingUri without wc: prefix}
  /// Example: wc://94caa59c...@2?relay-protocol=irn&symKey=...
  Future<_DeepLinkResult> _tryStrategyWcUniversalScheme(String wcUri) async {
    const name = 'Strategy: wc:// universal scheme';
    AppLogger.wallet(name);

    try {
      // Convert wc:... to wc://...
      // The WC URI starts with "wc:" so we replace it with "wc://"
      final wcSchemeUri = wcUri.replaceFirst('wc:', 'wc://');
      final uri = Uri.parse(wcSchemeUri);

      AppLogger.wallet('wc:// URI', data: {
        'originalPrefix': wcUri.substring(0, min(30, wcUri.length)),
        'convertedPrefix': wcSchemeUri.substring(0, min(30, wcSchemeUri.length)),
      });

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: wcSchemeUri,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'wc://...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 1: Non-encoded URI with Uri constructor
  Future<_DeepLinkResult> _tryStrategy1NonEncodedUri(String wcUri) async {
    const name = 'Strategy 1: okxwallet:// non-encoded (Uri constructor)';
    AppLogger.wallet(name);

    try {
      final schemeUri = Uri(
        scheme: 'okxwallet',
        host: 'wc',
        queryParameters: {'uri': wcUri},
      );

      final uriString = schemeUri.toString();
      AppLogger.wallet('Built URI', data: {
        'uri': uriString.length > 150 ? '${uriString.substring(0, 150)}...' : uriString,
      });

      final launched = await launchUrl(
        schemeUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: uriString,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'okxwallet://wc?uri=...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 2: Encoded URI with string parsing
  Future<_DeepLinkResult> _tryStrategy2EncodedUri(String encodedUri) async {
    const name = 'Strategy 2: okxwallet:// encoded';
    AppLogger.wallet(name);

    try {
      final schemeUrl = 'okxwallet://wc?uri=$encodedUri';
      final schemeUri = Uri.parse(schemeUrl);

      final launched = await launchUrl(
        schemeUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: schemeUrl,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'okxwallet://wc?uri=...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 3: Exchange app scheme (okx://)
  Future<_DeepLinkResult> _tryStrategy3ExchangeAppScheme(String encodedUri) async {
    const name = 'Strategy 3: okx:// (Exchange app WC)';
    AppLogger.wallet(name);

    try {
      // okx://wc?uri={encodedUri}
      final schemeUrl = 'okx://wc?uri=$encodedUri';
      final schemeUri = Uri.parse(schemeUrl);

      final launched = await launchUrl(
        schemeUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: schemeUrl,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'okx://wc?uri=...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 4: DApp browser approach (OKX official format)
  ///
  /// Per OKX documentation, the DApp browser deep link format is:
  /// okx://wallet/dapp/url?dappUrl={encodedUrl}
  ///
  /// However, for WalletConnect URIs, OKX may expect:
  /// - okx://wallet/dapp/wc?uri={encodedWcUri}  (WC-specific path)
  /// - Or the WC URI should be wrapped in a bridge URL
  Future<_DeepLinkResult> _tryStrategy4DappBrowser(String wcUri) async {
    const name = 'Strategy 4: okx://wallet/dapp/wc (WC-specific DApp path)';
    AppLogger.wallet(name);

    try {
      // Try WalletConnect-specific DApp path
      // This is more likely to trigger the WC handler in OKX
      final encodedWcUri = Uri.encodeComponent(wcUri);
      final dappUrl = 'okx://wallet/dapp/wc?uri=$encodedWcUri';
      final dappUri = Uri.parse(dappUrl);

      AppLogger.wallet('DApp browser URI', data: {
        'format': 'okx://wallet/dapp/wc?uri=...',
        'uriLength': wcUri.length,
        'encodedLength': encodedWcUri.length,
      });

      final launched = await launchUrl(
        dappUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: dappUrl,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'okx://wallet/dapp/url?dappUrl=...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 5: Universal Link with deeplink parameter (double-encoded)
  Future<_DeepLinkResult> _tryStrategy5UniversalLinkDeeplink(
    String doubleEncodedDeepLink,
  ) async {
    const name = 'Strategy 5: Universal Link with deeplink (double-encoded)';
    AppLogger.wallet(name);

    try {
      // Per OKX docs: https://web3.okx.com/download?deeplink={doubleEncoded}
      final universalUrl =
          'https://web3.okx.com/download?deeplink=$doubleEncodedDeepLink';
      final universalUri = Uri.parse(universalUrl);

      final launched = await launchUrl(
        universalUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: universalUrl,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'https://web3.okx.com/download?deeplink=...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 6: Universal Link with uri parameter (single-encoded)
  Future<_DeepLinkResult> _tryStrategy6UniversalLinkUri(String encodedUri) async {
    const name = 'Strategy 6: Universal Link with uri (single-encoded)';
    AppLogger.wallet(name);

    try {
      final universalUrl = '${WalletConstants.okxWalletUniversalLink}?uri=$encodedUri';
      final universalUri = Uri.parse(universalUrl);

      final launched = await launchUrl(
        universalUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: universalUrl,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'https://web3.okx.com/download?uri=...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Strategy 7: Raw wc: URI (OS picker)
  Future<_DeepLinkResult> _tryStrategy7RawWcUri(String wcUri) async {
    const name = 'Strategy 7: Raw WC URI (OS picker)';
    AppLogger.wallet(name);

    try {
      final rawUri = Uri.parse(wcUri);
      final launched = await launchUrl(
        rawUri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        AppLogger.wallet('$name SUCCESS');
      } else {
        AppLogger.wallet('$name: launchUrl returned false');
      }

      return _DeepLinkResult(
        strategyName: name,
        uri: wcUri,
        launched: launched,
      );
    } catch (e) {
      AppLogger.w('$name FAILED: $e');
      return _DeepLinkResult(
        strategyName: name,
        uri: 'wc:...',
        launched: false,
        error: e.toString(),
      );
    }
  }

  /// Build double-encoded deep link per OKX documentation
  String _buildDoubleEncodedDeepLink(String wcUri) {
    // First encoding: the WC URI
    final encodedWcUri = Uri.encodeComponent(wcUri);
    // Build the inner deep link
    final innerDeepLink = 'okx://wallet/dapp/url?dappUrl=$encodedWcUri';
    // Second encoding: the entire deep link
    return Uri.encodeComponent(innerDeepLink);
  }

  /// Log detailed URI information for debugging
  void _logUriDetails(String wcUri) {
    AppLogger.wallet('WC URI Analysis', data: {
      'length': wcUri.length,
      'prefix': wcUri.substring(0, min(100, wcUri.length)),
      'containsAt': wcUri.contains('@'),
      'containsQuestion': wcUri.contains('?'),
      'versionPart': _extractWcVersion(wcUri),
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
    });
  }

  /// Extract WalletConnect version from URI
  String _extractWcVersion(String wcUri) {
    // Extract version from wc:...@2?... format
    final atIndex = wcUri.indexOf('@');
    if (atIndex > 0 && atIndex < wcUri.length - 1) {
      final afterAt = wcUri.substring(atIndex + 1);
      final questionIndex = afterAt.indexOf('?');
      return afterAt.substring(
        0,
        questionIndex > 0 ? questionIndex : min(5, afterAt.length),
      );
    }
    return 'unknown';
  }

  /// Log all failed attempts for comprehensive diagnostics
  void _logAllFailedAttempts(List<_DeepLinkResult> attempts) {
    AppLogger.wallet('=== ALL STRATEGIES FAILED ===');
    AppLogger.wallet('Diagnostic summary', data: {
      'totalAttempts': attempts.length,
      'platform': Platform.operatingSystem,
      'platformVersion': Platform.operatingSystemVersion,
    });

    for (int i = 0; i < attempts.length; i++) {
      final attempt = attempts[i];
      AppLogger.wallet('Attempt ${i + 1}', data: {
        'strategy': attempt.strategyName,
        'launched': attempt.launched,
        'error': attempt.error ?? 'none',
      });
    }

    AppLogger.wallet('Troubleshooting suggestions', data: {
      'checkInstalled': 'Verify OKX Wallet app is installed',
      'checkScheme': 'Try both okx:// and okxwallet:// schemes manually',
      'checkVersion': 'Ensure OKX Wallet is updated to latest version',
      'killApp': 'Force quit OKX Wallet and try again',
      'manualTest': 'Test deep link manually: okxwallet://wc',
    });
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

  /// Validate session - only accept OKX Wallet sessions
  /// This prevents cross-wallet session conflicts (e.g., Trust Wallet session being reused)
  ///
  /// Validation strategy:
  /// 1. Accept if name contains 'okx' or 'okex'
  /// 2. Reject if name clearly belongs to another wallet
  /// 3. Accept unknown/empty names (benefit of the doubt for new sessions)
  @override
  bool validateWalletSpecific(SessionData session) {
    final peer = session.peer;
    final name = peer.metadata.name.toLowerCase();
    final redirect = peer.metadata.redirect?.native?.toLowerCase() ?? '';

    AppLogger.wallet('Session validation check', data: {
      'peerName': name,
      'redirect': redirect,
    });

    // Accept if clearly OKX
    if (name.contains('okx') || name.contains('okex')) {
      AppLogger.wallet('Session ACCEPTED: OKX name match');
      return true;
    }

    // Accept if redirect contains okxwallet or okx:// scheme
    // Note: Both schemes may be used depending on which app/version responds
    if (redirect.contains('okxwallet') || redirect.contains('okx://')) {
      AppLogger.wallet('Session ACCEPTED: OKX redirect match', data: {
        'redirect': redirect,
      });
      return true;
    }

    // Reject if clearly another wallet
    final otherWallets = ['metamask', 'trust', 'phantom', 'rabby', 'rainbow', 'coinbase'];
    for (final wallet in otherWallets) {
      if (name.contains(wallet)) {
        AppLogger.wallet('Session REJECTED: belongs to $wallet');
        return false;
      }
    }

    // Accept unknown sessions (may be OKX with different metadata)
    if (name.isEmpty) {
      AppLogger.wallet('Session ACCEPTED: empty name (new session)');
      return true;
    }

    // Default: accept unknown wallet names
    AppLogger.wallet('Session ACCEPTED: unknown wallet "$name" (benefit of doubt)');
    return true;
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

    try {
      // === CRITICAL FIX: Use prepareConnection() pattern (like MetaMask) ===
      // This ensures the session proposal is fully published to the relay
      // server BEFORE we open the wallet app.
      //
      // Previous issue: unawaited(super.connect()) didn't wait for relay
      // acknowledgment, causing the wallet to query an empty relay.
      AppLogger.wallet('Preparing connection (awaiting relay acknowledgment)...');
      final sessionFuture = await prepareConnection(chainId: chainId);

      // Get the generated URI (now guaranteed to be on relay)
      final uri = await getConnectionUri();
      if (uri == null) {
        throw const WalletException(
          message: 'Failed to generate connection URI',
          code: 'URI_GENERATION_FAILED',
        );
      }

      // === CRITICAL FIX: Add relay propagation margin BEFORE opening wallet ===
      // Even after prepareConnection() returns, there may be network latency
      // before the proposal is fully queryable by the wallet app.
      AppLogger.wallet('Waiting for relay propagation margin...');
      await Future.delayed(AppConstants.okxRelayPropagationDelay);

      // Open OKX Wallet with the URI
      // Throws WalletNotInstalledException if app is not installed
      AppLogger.wallet('Opening OKX Wallet...');
      await openWithUri(uri);

      // Wait for connection with extended timeout + recovery polling
      AppLogger.wallet('Waiting for wallet approval...');
      try {
        final wallet = await sessionFuture.timeout(
          AppConstants.connectionTimeout,
          onTimeout: () async {
            // OXK-specific timeout recovery with soft timeout support:
            // Distinguish between "hard timeout" (user didn't respond) and
            // "soft timeout" (timeout occurred while app was in background)
            AppLogger.wallet('Timeout reached, analyzing context...');

            // Check accumulated background time
            final bgTime = accumulatedBackgroundTime;
            final wasInBackground = bgTime > AppConstants.softTimeoutThreshold;

            AppLogger.wallet('Timeout analysis', data: {
              'backgroundTime': bgTime.inSeconds,
              'threshold': AppConstants.softTimeoutThreshold.inSeconds,
              'isSoftTimeout': wasInBackground,
            });

            // STEP 0: IMMEDIATE optimistic session check (no delay)
            // Check if session was already stored but we missed the event
            AppLogger.wallet('🔍 Timeout recovery: optimistic session check...');
            await optimisticSessionCheck();

            if (isConnected && connectedAddress != null) {
              AppLogger.wallet('✅ Connected via optimistic check at timeout!');
              return WalletEntity(
                address: connectedAddress!,
                type: walletType,
                chainId: requestedChainId ?? currentChainId,
                connectedAt: DateTime.now(),
                metadata: {'recoveredAtTimeout': true},
              );
            }

            // GRACE PERIOD: Wait for any pending deep link to arrive and be processed
            // This handles the case where the user approved in OKX and is returning
            // to the app, but the deep link hasn't arrived yet at timeout
            AppLogger.wallet('Checking for pending deep link...');
            final graceEnd = DateTime.now().add(AppConstants.deepLinkGracePeriod);
            while (DateTime.now().isBefore(graceEnd)) {
              // Check if deep link is currently being processed
              if (_deepLinkPending) {
                AppLogger.wallet('Deep link pending, waiting for processing...');
                await Future.delayed(const Duration(milliseconds: 100));

                // If connected during grace period, return immediately
                if (isConnected && connectedAddress != null) {
                  AppLogger.wallet('Connected during grace period!');
                  return WalletEntity(
                    address: connectedAddress!,
                    type: walletType,
                    chainId: requestedChainId ?? currentChainId,
                    connectedAt: DateTime.now(),
                    metadata: {'recoveredDuringGracePeriod': true},
                  );
                }
              }
              await Future.delayed(const Duration(milliseconds: 50));
            }

            // ===== SOFT TIMEOUT HANDLING =====
            // If we were in background for significant time, this is a SOFT TIMEOUT
            // Don't give up yet - mark for recovery when user returns
            if (wasInBackground) {
              AppLogger.wallet('SOFT TIMEOUT: Background for ${bgTime.inSeconds}s');
              markSoftTimeout();
              _pendingPostTimeoutRecovery = true;

              throw WalletException(
                message: 'OKX 지갑에서 승인을 기다리고 있습니다.\n'
                    '승인 후 이 앱으로 돌아와 주세요.',
                code: 'SOFT_TIMEOUT',
              );
            }

            // ===== HARD TIMEOUT HANDLING =====
            // Grace period expired, try aggressive session recovery
            AppLogger.wallet('Hard timeout, attempting session recovery...');

            // Try aggressive relay reconnection + session polling
            final recoveredWallet = await _attemptSessionRecovery();
            if (recoveredWallet != null) {
              return recoveredWallet;
            }

            throw const WalletException(
              message: 'Connection timed out. '
                  'If you approved in OKX Wallet, please try:\n'
                  '1. Return to this app and wait a moment\n'
                  '2. Or tap "Retry Connection" below',
              code: 'TIMEOUT',
            );
          },
        );

        AppLogger.wallet('OKX Wallet connection successful', data: {
          'address': wallet.address,
          'chainId': wallet.chainId,
        });

        // Return wallet with correct type
        return wallet.copyWith(type: walletType);
      } on WalletException catch (e) {
        // If timeout with recovery failed, keep waiting flag active for manual recovery
        // Don't clear _isWaitingForApproval yet - user might still be approving
        if (e.code == 'TIMEOUT') {
          AppLogger.wallet('Timeout with recovery attempt failed, keeping approval flag for app resume');
          // Rethrow to UI for user feedback
        }
        rethrow;
      }
    } catch (e) {
      AppLogger.e('OKX Wallet connection failed', e);
      rethrow;
    }
  }

  /// Attempt to recover session after timeout
  ///
  /// This handles the case where:
  /// 1. User approved in OKX Wallet while app was in background
  /// 2. Relay disconnected due to Android background network restrictions
  /// 3. Session exists but wasn't synced due to relay disconnection
  ///
  /// Recovery strategy:
  /// - Aggressively reconnect relay with multiple attempts
  /// - Poll for session existence even without relay events
  /// - Use progressive timeouts (3s → 4s → 5s)
  Future<WalletEntity?> _attemptSessionRecovery() async {
    AppLogger.wallet('=== OKX Session Recovery START ===');

    // Phase 3.3: Use generalized reconnection config when enabled
    final config = AppConstants.enableGeneralizedReconnectionConfig
        ? walletType.reconnectionConfig
        : null;

    // Step 1: Pre-poll delay to allow any pending relay events to arrive
    final prePollDelay = config?.prePollDelay ?? AppConstants.okxPrePollDelay;
    await Future.delayed(prePollDelay);

    // Step 2: Progressive relay reconnection attempts
    final reconnectTimeouts = config?.reconnectTimeouts ?? AppConstants.okxReconnectTimeouts;
    final reconnectDelay = config?.reconnectDelay ?? AppConstants.okxReconnectDelay;

    for (int i = 0; i < reconnectTimeouts.length; i++) {
      final timeoutSeconds = reconnectTimeouts[i];
      AppLogger.wallet('Recovery attempt ${i + 1}/${reconnectTimeouts.length}', data: {
        'timeout': '${timeoutSeconds}s',
        'usingGeneralizedConfig': config != null,
      });

      final relayConnected = await ensureRelayConnected(
        timeout: Duration(seconds: timeoutSeconds),
      );

      if (relayConnected) {
        AppLogger.wallet('Relay reconnected, checking for session...');
        // Small delay for session sync after relay reconnection
        await Future.delayed(const Duration(milliseconds: 500));

        // Check if session is now available
        final wallet = await _checkForEstablishedSession();
        if (wallet != null) {
          AppLogger.wallet('=== Session recovered successfully! ===');
          return wallet;
        }
      }

      // Delay before next attempt (except on last iteration)
      if (i < reconnectTimeouts.length - 1) {
        await Future.delayed(reconnectDelay);
      }
    }

    // Step 3: Final session polling without relay (optimistic check)
    // Even if relay failed, session might exist in storage
    final maxPolls = config?.maxSessionPolls ?? AppConstants.okxMaxSessionPolls;
    final pollInterval = config?.sessionPollInterval ?? AppConstants.okxSessionPollInterval;

    AppLogger.wallet('Final optimistic session check without relay...');
    for (int poll = 0; poll < maxPolls; poll++) {
      final wallet = await _checkForEstablishedSession();
      if (wallet != null) {
        AppLogger.wallet('=== Session found without relay! ===');
        return wallet;
      }

      if (poll < maxPolls - 1) {
        await Future.delayed(pollInterval);
      }
    }

    AppLogger.wallet('=== Session recovery FAILED after all attempts ===');
    return null;
  }

  /// Check if a valid OKX session has been established
  ///
  /// This is used during session recovery to poll for approved sessions
  /// even when relay events were missed.
  Future<WalletEntity?> _checkForEstablishedSession() async {
    // Use the parent's checkConnectionOnResume which handles session validation and state updates
    await checkConnectionOnResume();

    // After calling checkConnectionOnResume, check if we're now connected
    if (isConnected && connectedAddress != null) {
      AppLogger.wallet('Session recovered via checkConnectionOnResume');

      final wallet = WalletEntity(
        address: connectedAddress!,
        type: walletType,
        chainId: requestedChainId ?? currentChainId,
        connectedAt: DateTime.now(),
        metadata: {
          'recoveredAfterTimeout': true,
        },
      );

      return wallet;
    }

    return null;
  }
}
