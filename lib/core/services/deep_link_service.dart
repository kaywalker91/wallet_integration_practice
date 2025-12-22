import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wallet_integration_practice/core/services/sentry_service.dart';
import 'package:wallet_integration_practice/core/services/wallet_log_service.dart';
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
  final _errorController = StreamController<DeepLinkError>.broadcast();

  /// Stream of incoming deep links
  Stream<Uri> get deepLinkStream => _deepLinkController.stream;

  /// Stream of deep link handling errors for UI feedback
  Stream<DeepLinkError> get errorStream => _errorController.stream;

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
    // *** CRITICAL: Log ALL incoming deep links ***
    // This captures every deep link that enters the app, regardless of handler
    WalletLogService.instance.logDeepLinkReturn(uri);

    _deepLinkController.add(uri);

    // Route to registered handlers
    for (final entry in _handlers.entries) {
      if (uri.path.startsWith(entry.key) || uri.host == entry.key) {
        try {
          await entry.value(uri);
          return;
        } catch (e) {
          AppLogger.e('Error in deep link handler for ${entry.key}', e);
          // Emit error to stream so UI can display feedback to user
          _errorController.add(DeepLinkError(
            handlerKey: entry.key,
            uri: uri,
            error: e,
            message: 'Failed to process wallet callback: ${e.toString()}',
          ));
          // Don't continue to other handlers on error - the matched handler failed
          return;
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

    AppLogger.i('🔔 Routing wallet callback: scheme=$scheme, host=$host, path=$path');
    AppLogger.i('📋 Registered handlers: ${_handlers.keys.toList()}');

    // Handle empty deep link callback (wip:// with no host/path)
    // This happens when wallet app returns to our app without specific callback data
    if (scheme == 'wip' && host.isEmpty && path.isEmpty) {
      AppLogger.i('📱 App resumed from wallet (empty callback)');
      if (_handlers.containsKey('app_resumed')) {
        await _invokeHandlerSafely('app_resumed', uri);
        return;
      }
      // No handler registered is OK - app lifecycle observer will handle this
      AppLogger.d('No app_resumed handler registered (handled by lifecycle observer)');
      return;
    }

    // Phantom callback: wip://phantom/callback?...
    if (host == 'phantom' || path.contains('phantom')) {
      if (_handlers.containsKey('phantom')) {
        AppLogger.i('✅ Found phantom handler, invoking...');
        await _invokeHandlerSafely('phantom', uri);
        return;
      } else {
        AppLogger.e('❌ Phantom handler NOT registered! Available: ${_handlers.keys.toList()}');
      }
    }

    // MetaMask callback: wip://metamask/callback?...
    if (host == 'metamask' || path.contains('metamask')) {
      if (_handlers.containsKey('metamask')) {
        AppLogger.i('✅ Found metamask handler, invoking...');
        await _invokeHandlerSafely('metamask', uri);
        return;
      } else {
        AppLogger.e('❌ MetaMask handler NOT registered! Available: ${_handlers.keys.toList()}');
      }
    }

    // WalletConnect callback: wip://wc?...
    if (host == 'wc' || path.contains('wc')) {
      if (_handlers.containsKey('walletconnect')) {
        AppLogger.i('✅ Found walletconnect handler, invoking...');
        await _invokeHandlerSafely('walletconnect', uri);
        return;
      } else if (_handlers.containsKey('wc')) {
        AppLogger.i('✅ Found wc handler, invoking...');
        await _invokeHandlerSafely('wc', uri);
        return;
      } else {
        AppLogger.e('❌ WalletConnect handler NOT registered! Available: ${_handlers.keys.toList()}');
      }
    }

    // Generic callback handler
    if (_handlers.containsKey('default')) {
      AppLogger.i('Using default handler');
      await _invokeHandlerSafely('default', uri);
    } else {
      AppLogger.w('⚠️ No handler found for URI: $uri');
    }
  }

  /// Safely invoke a registered handler with error handling
  ///
  /// This prevents StateError and other exceptions from crashing the app
  /// when WebSocket channels are closed during relay reconnection.
  Future<void> _invokeHandlerSafely(String handlerKey, Uri uri) async {
    try {
      await _handlers[handlerKey]!(uri);
    } catch (e, st) {
      AppLogger.e('Deep link handler error for $handlerKey (non-fatal)', e);

      // Track in Sentry as warning since this is often recoverable
      // Using unawaited() to explicitly mark fire-and-forget async call
      unawaited(SentryService.instance.captureException(
        e,
        stackTrace: st,
        level: SentryLevel.warning,
        tags: {'error_type': 'deep_link_handler', 'handler_key': handlerKey},
        extras: {'uri': uri.toString()},
      ));

      // Emit error to stream so UI can display feedback to user
      _errorController.add(DeepLinkError(
        handlerKey: handlerKey,
        uri: uri,
        error: e,
        message: 'Deep link handler error: ${e.toString()}',
      ));
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _deepLinkController.close();
    await _errorController.close();
    _handlers.clear();
  }
}

/// Error information for deep link handling failures
class DeepLinkError {
  final String handlerKey;
  final Uri uri;
  final Object error;
  final String message;
  final DateTime timestamp;

  DeepLinkError({
    required this.handlerKey,
    required this.uri,
    required this.error,
    required this.message,
  }) : timestamp = DateTime.now();

  @override
  String toString() => 'DeepLinkError(handler: $handlerKey, message: $message)';
}
