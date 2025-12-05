import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';

/// Callback type for deep link handling
typedef DeepLinkCallback = Future<void> Function(Uri uri);

/// Service for handling deep links from wallet apps
class DeepLinkService {
  static DeepLinkService? _instance;
  static DeepLinkService get instance => _instance ??= DeepLinkService._();

  DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  final Map<String, DeepLinkCallback> _handlers = {};
  final _deepLinkController = StreamController<Uri>.broadcast();

  /// Stream of incoming deep links
  Stream<Uri> get deepLinkStream => _deepLinkController.stream;

  /// Initialize the deep link service
  Future<void> initialize() async {
    AppLogger.i('Initializing DeepLinkService');

    // Handle initial link if app was launched from a deep link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        AppLogger.i('Initial deep link: $initialUri');
        await _handleDeepLink(initialUri);
      }
    } catch (e) {
      AppLogger.e('Error getting initial link', e);
    }

    // Listen for incoming deep links while app is running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) async {
        AppLogger.i('Received deep link: $uri');
        await _handleDeepLink(uri);
      },
      onError: (error) {
        AppLogger.e('Deep link stream error', error);
      },
    );

    AppLogger.i('DeepLinkService initialized');
  }

  /// Register a handler for a specific path prefix
  void registerHandler(String pathPrefix, DeepLinkCallback callback) {
    _handlers[pathPrefix] = callback;
    AppLogger.d('Registered deep link handler for: $pathPrefix');
  }

  /// Unregister a handler
  void unregisterHandler(String pathPrefix) {
    _handlers.remove(pathPrefix);
  }

  /// Handle incoming deep link
  Future<void> _handleDeepLink(Uri uri) async {
    _deepLinkController.add(uri);

    // Route to registered handlers
    for (final entry in _handlers.entries) {
      if (uri.path.startsWith(entry.key) || uri.host == entry.key) {
        try {
          await entry.value(uri);
          return;
        } catch (e) {
          AppLogger.e('Error in deep link handler for ${entry.key}', e);
        }
      }
    }

    // Handle known wallet callback patterns
    await _routeWalletCallback(uri);
  }

  /// Route wallet-specific callbacks
  Future<void> _routeWalletCallback(Uri uri) async {
    final scheme = uri.scheme;
    final host = uri.host;
    final path = uri.path;

    AppLogger.d('Routing wallet callback: scheme=$scheme, host=$host, path=$path');

    // Phantom callback: wip://phantom/callback?...
    if (host == 'phantom' || path.contains('phantom')) {
      if (_handlers.containsKey('phantom')) {
        await _handlers['phantom']!(uri);
        return;
      }
    }

    // MetaMask callback: wip://metamask/callback?...
    if (host == 'metamask' || path.contains('metamask')) {
      if (_handlers.containsKey('metamask')) {
        await _handlers['metamask']!(uri);
        return;
      }
    }

    // WalletConnect callback: wip://wc?...
    if (host == 'wc' || path.contains('wc')) {
      if (_handlers.containsKey('walletconnect')) {
        await _handlers['walletconnect']!(uri);
        return;
      }
    }

    // Generic callback handler
    if (_handlers.containsKey('default')) {
      await _handlers['default']!(uri);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _deepLinkController.close();
    _handlers.clear();
  }
}
