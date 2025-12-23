import 'dart:async' show Completer, StreamSubscription, unawaited;
import 'dart:io';
import 'dart:math' show min;
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

  @override
  WalletType get walletType => WalletType.okxWallet;

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

      // Fall back to relay-based check with delay
      await Future.delayed(const Duration(milliseconds: 300));

      // Directly call the protected method instead of lifecycle callback
      await checkConnectionOnResume();
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
  /// Uses an 8-strategy approach to maximize compatibility:
  ///
  /// Priority order (based on WalletConnect docs and OKX behavior):
  /// 1. wc:// scheme (WalletConnect universal scheme - triggers OS wallet picker)
  /// 2. okx://wc?uri= (Exchange app WC scheme)
  /// 3. okxwallet://wc?uri= encoded (Standard WC format for wallet apps)
  /// 4. okxwallet://wc?uri= non-encoded (Uri constructor)
  /// 5. okx://wallet/dapp/wc?uri= (OKX DApp browser WC path)
  /// 6. Universal Link with deeplink (double-encoded)
  /// 7. Universal Link with uri (single-encoded)
  /// 8. Raw wc: URI (direct WC URI)
  ///
  /// Note: OKX has two apps with different schemes:
  /// - OKX Wallet (com.okx.wallet) → 'okxwallet://'
  /// - OKX Exchange (com.okinc.okex) → 'okx://'
  Future<bool> openWithUri(String wcUri) async {
    AppLogger.wallet('=== OKX Wallet openWithUri() START ===');
    _logUriDetails(wcUri);

    // Prepare encoded versions
    final encodedUri = Uri.encodeComponent(wcUri);
    final doubleEncodedDeepLink = _buildDoubleEncodedDeepLink(wcUri);

    AppLogger.wallet('Encoding summary', data: {
      'originalLength': wcUri.length,
      'encodedLength': encodedUri.length,
      'doubleEncodedLength': doubleEncodedDeepLink.length,
    });

    // Track all attempts for diagnostic purposes
    final List<_DeepLinkResult> attempts = [];

    // NEW PRIORITY ORDER (based on WalletConnect v2 docs and OKX behavior):
    // 1. wc:// universal scheme (triggers OS wallet picker with WC support)
    // 2. okx://wc?uri= (Exchange app WC scheme - may work for both apps)
    // 3. okxwallet://wc?uri= encoded (Standard WC format)
    // 4. okxwallet://wc?uri= non-encoded (Uri constructor)
    // 5. OKX DApp browser WC path
    // 6-8. Universal links and raw WC URI as fallbacks

    // Strategy 1: wc:// universal scheme (WalletConnect universal handler)
    // Per WalletConnect docs, wallets should register "wc://" to handle pairing
    var result = await _tryStrategyWcUniversalScheme(wcUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using wc:// universal scheme');
      return true;
    }

    // Strategy 2: okx://wc?uri= (Exchange app WC scheme)
    result = await _tryStrategy3ExchangeAppScheme(encodedUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using okx://wc?uri= scheme');
      return true;
    }

    // Strategy 3: okxwallet://wc?uri= (Encoded)
    result = await _tryStrategy2EncodedUri(encodedUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using okxwallet://wc?uri= encoded scheme');
      return true;
    }

    // Strategy 4: okxwallet://wc?uri= (Non-encoded, Uri constructor)
    result = await _tryStrategy1NonEncodedUri(wcUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using okxwallet://wc?uri= non-encoded scheme');
      return true;
    }

    // Strategy 5: okx://wallet/dapp/wc?uri= (OKX DApp browser WC path)
    result = await _tryStrategy4DappBrowser(wcUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using OKX DApp browser WC path');
      return true;
    }

    // Strategy 6: Universal Link with deeplink (double-encoded)
    result = await _tryStrategy5UniversalLinkDeeplink(doubleEncodedDeepLink);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using Universal Link with double-encoded deeplink');
      return true;
    }

    // Strategy 7: Universal Link with uri (single-encoded)
    result = await _tryStrategy6UniversalLinkUri(encodedUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using Universal Link with single-encoded uri');
      return true;
    }

    // Strategy 8: Raw wc: URI (OS picker)
    result = await _tryStrategy7RawWcUri(wcUri);
    attempts.add(result);
    if (result.launched) {
      AppLogger.wallet('🎯 Using raw wc: URI with OS picker');
      return true;
    }

    // All strategies failed - log comprehensive diagnostic
    _logAllFailedAttempts(attempts);

    throw WalletNotInstalledException(
      walletType: walletType.name,
      message: 'OKX Wallet is not installed or failed to process WC URI. '
          'Tried ${attempts.length} strategies.',
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
  ///
  /// Validation strategy:
  /// 1. Accept if name contains 'okx' or 'okex'
  /// 2. Reject if name clearly belongs to another wallet
  /// 3. Accept unknown/empty names (benefit of the doubt for new sessions)
  @override
  bool isSessionValid(SessionData session) {
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

    // Set up connection tracking
    final completer = Completer<WalletEntity>();
    StreamSubscription? subscription;

    // Subscribe to connection stream with enhanced error handling
    // This protects against "Bad state: Cannot add event after closing" errors
    subscription = connectionStream.listen(
      (status) {
        try {
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
        } catch (e, stackTrace) {
          // Catch any errors during status processing (including stream errors)
          AppLogger.e('Error processing connection status', e, stackTrace);
          // Don't complete with error here - let the timeout handle it
        }
      },
      onError: (error, stackTrace) {
        AppLogger.e('Connection stream error', error, stackTrace);
        // Only complete with error if this is a genuine stream error
        // and not a "Bad state" from disposed controller
        if (!completer.isCompleted && error is! StateError) {
          completer.completeError(
            WalletException(
              message: 'Connection stream error: $error',
              code: 'STREAM_ERROR',
            ),
          );
        }
      },
      // Cancel on error to prevent further "Bad state" errors
      cancelOnError: false,
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

      // IMPORTANT: Add delay for OKX's redirect behavior
      // OKX may redirect back to our app before the WalletConnect
      // session is fully established. This delay helps stabilize the connection.
      AppLogger.wallet('Waiting for OKX redirect stabilization...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Wait for connection with extended timeout + recovery polling
      AppLogger.wallet('Waiting for wallet approval...');
      try {
        final wallet = await completer.future.timeout(
          AppConstants.connectionTimeout,
          onTimeout: () async {
            // OKX-specific timeout recovery:
            // User may have approved in OKX but session not synced due to relay disconnection
            AppLogger.wallet('Timeout reached, starting recovery sequence...');

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

            // Grace period expired, try aggressive session recovery
            AppLogger.wallet('Grace period expired, attempting session recovery...');

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

        return wallet;
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
    } finally {
      await subscription.cancel();
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

    // Step 1: Pre-poll delay to allow any pending relay events to arrive
    await Future.delayed(AppConstants.okxPrePollDelay);

    // Step 2: Progressive relay reconnection attempts
    for (int i = 0; i < AppConstants.okxReconnectTimeouts.length; i++) {
      final timeoutSeconds = AppConstants.okxReconnectTimeouts[i];
      AppLogger.wallet('Recovery attempt ${i + 1}/${AppConstants.okxReconnectTimeouts.length}', data: {
        'timeout': '${timeoutSeconds}s',
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
      if (i < AppConstants.okxReconnectTimeouts.length - 1) {
        await Future.delayed(AppConstants.okxReconnectDelay);
      }
    }

    // Step 3: Final session polling without relay (optimistic check)
    // Even if relay failed, session might exist in storage
    AppLogger.wallet('Final optimistic session check without relay...');
    for (int poll = 0; poll < AppConstants.okxMaxSessionPolls; poll++) {
      final wallet = await _checkForEstablishedSession();
      if (wallet != null) {
        AppLogger.wallet('=== Session found without relay! ===');
        return wallet;
      }

      if (poll < AppConstants.okxMaxSessionPolls - 1) {
        await Future.delayed(AppConstants.okxSessionPollInterval);
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
