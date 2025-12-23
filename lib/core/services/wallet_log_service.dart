import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../constants/wallet_constants.dart';
import '../models/wallet_log_context.dart';
import '../models/wallet_log_enums.dart';
import '../models/wallet_log_models.dart';
import '../utils/logger.dart';
import 'debug_log_service.dart';
import 'sentry_service.dart';

/// Central service for structured wallet connection logging
///
/// This service provides:
/// - Unique connectionId generation for each connection attempt
/// - State machine tracking for the connection flow
/// - Structured logging with consistent context
/// - Integration with DebugLogService and Sentry
/// - Approval timeout detection
///
/// Usage:
/// ```dart
/// // Start a connection
/// WalletLogService.instance.startConnection(
///   walletType: WalletType.metamask,
///   chainId: 1,
/// );
///
/// // Log state transitions
/// WalletLogService.instance.transitionTo(WalletConnectionStep.wcUriReceived);
///
/// // Log deep link return (useful for deep link debugging)
/// WalletLogService.instance.logDeepLinkReturn(uri);
///
/// // End connection
/// WalletLogService.instance.endConnection(success: true);
/// ```
class WalletLogService {
  WalletLogService._();

  static WalletLogService? _instance;

  /// Singleton instance
  static WalletLogService get instance => _instance ??= WalletLogService._();


  /// Current connection context (null when no connection in progress)
  WalletLogContext? _context;

  /// Get current context (read-only)
  WalletLogContext? get context => _context;

  /// Whether a connection is currently in progress
  bool get hasActiveConnection => _context != null;

  /// Approval timeout timer
  Timer? _approvalTimeoutTimer;

  /// Approval timeout duration
  static const Duration approvalTimeout = Duration(seconds: 60);

  /// Stream controller for wallet log events
  final _logStreamController = StreamController<WalletLogEvent>.broadcast();

  /// Stream of wallet log events for UI updates
  Stream<WalletLogEvent> get logStream => _logStreamController.stream;

  // ============================================================================
  // Connection Lifecycle Methods
  // ============================================================================

  /// Start a new connection attempt
  ///
  /// Creates a new context with unique connectionId.
  /// Call this when the user initiates a wallet connection.
  WalletLogContext startConnection({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) {
    // End any existing connection first
    if (_context != null) {
      _log(
        'Previous connection not ended, cleaning up',
        level: WalletLogLevel.warning,
      );
      _cleanup();
    }

    _context = WalletLogContext.start(
      walletType: walletType,
      chainId: chainId,
      cluster: cluster,
    );

    _logTransition('Connection started');

    // Track in Sentry
    SentryService.instance.trackWalletConnectionStart(
      walletType: walletType.name,
      chainId: chainId,
      cluster: cluster,
    );

    return _context!;
  }

  /// End the current connection (success or failure)
  ///
  /// Always call this when the connection flow completes.
  void endConnection({bool success = false}) {
    if (_context == null) return;

    _cancelApprovalTimeout();

    if (success) {
      _context = _context!.transitionTo(WalletConnectionStep.sessionEstablished);
      _logTransition('Connection completed successfully');

      SentryService.instance.trackWalletConnectionSuccess(
        walletType: _context!.walletType.name,
        address: 'connected',  // Actual address logged elsewhere
        chainId: _context!.chainId,
        cluster: _context!.cluster,
      );
    } else {
      _logTransition('Connection ended (failed or cancelled)');
    }

    _cleanup();
  }

  /// Clean up resources
  void _cleanup() {
    _cancelApprovalTimeout();
    _context = null;
  }

  // ============================================================================
  // State Transition Methods
  // ============================================================================

  /// Transition to a new step
  ///
  /// This is the primary method for tracking progress through the connection flow.
  void transitionTo(WalletConnectionStep newStep, {String? message}) {
    if (_context == null) {
      AppLogger.w('[WALLET] Transition called without active connection: $newStep');
      return;
    }

    final previousStep = _context!.step;
    _context = _context!.transitionTo(newStep);
    _logTransition(message ?? 'Step: ${newStep.displayName}');

    // Handle approval-related transitions
    if (newStep == WalletConnectionStep.awaitingApproval) {
      _startApprovalTimeout();
    }

    if (newStep == WalletConnectionStep.approvalReceived ||
        newStep == WalletConnectionStep.approvalRejected ||
        newStep == WalletConnectionStep.sessionEstablished) {
      _cancelApprovalTimeout();
    }

    // Emit event for UI
    _emitEvent(WalletLogEvent(
      type: WalletLogEventType.stateTransition,
      step: newStep,
      previousStep: previousStep,
      context: _context,
    ));
  }

  /// Update relay state
  void updateRelayState(RelayState newState, {
    bool isReconnecting = false,
    String? errorMessage,
  }) {
    if (_context == null) return;

    final previousState = _context!.relayState;
    _context = _context!.copyWith(
      relayState: newState,
      isReconnecting: isReconnecting,
      errorMessage: newState == RelayState.error ? errorMessage : null,
    );

    _log(
      'Relay: ${previousState.displayName} -> ${newState.displayName}${isReconnecting ? ' (reconnecting)' : ''}',
      level: newState == RelayState.error ? WalletLogLevel.warning : WalletLogLevel.info,
    );

    _emitEvent(WalletLogEvent(
      type: WalletLogEventType.relayStateChange,
      relayState: newState,
      previousRelayState: previousState,
      context: _context,
    ));
  }

  /// Update session state
  void updateSessionState(
    WcSessionState newState, {
    String? sessionTopic,
    String? peerName,
  }) {
    if (_context == null) return;

    final previousState = _context!.sessionState;
    _context = _context!.copyWith(
      sessionState: newState,
      sessionTopic: sessionTopic ?? _context!.sessionTopic,
      peerName: peerName ?? _context!.peerName,
    );

    _log('Session: ${previousState.displayName} -> ${newState.displayName}');

    // Automatically transition step based on session state
    if (newState == WcSessionState.approved) {
      transitionTo(
        WalletConnectionStep.approvalReceived,
        message: '*** APPROVAL RECEIVED - Session approved ***',
      );
    } else if (newState == WcSessionState.rejected) {
      transitionTo(
        WalletConnectionStep.approvalRejected,
        message: 'Session rejected by user',
      );
    }

    _emitEvent(WalletLogEvent(
      type: WalletLogEventType.sessionStateChange,
      sessionState: newState,
      previousSessionState: previousState,
      context: _context,
    ));
  }

  /// Update lifecycle state
  void updateLifecycleState(AppLifecycleState state) {
    if (_context == null) return;

    final previous = _context!.lifecycleState;
    _context = _context!.copyWith(lifecycleState: state);

    _log('Lifecycle: ${previous?.name ?? 'null'} -> ${state.name}');
  }

  // ============================================================================
  // Event Logging Methods
  // ============================================================================

  /// Log WC URI generation
  void logWcUriGenerated(String wcUri) {
    if (_context == null) return;

    final uriInfo = WcUriInfo.fromUri(wcUri);
    _context = _context!.copyWith(wcUriInfo: uriInfo);
    transitionTo(
      WalletConnectionStep.wcUriReceived,
      message: 'WC URI generated (${uriInfo.uriLength} chars)',
    );
  }

  /// Log deep link dispatch attempt
  void logDeepLinkDispatch(DeepLinkDispatchInfo info) {
    if (_context == null) return;

    _context = _context!.copyWith(deepLinkInfo: info);

    if (info.launched) {
      transitionTo(
        WalletConnectionStep.deeplinkDispatched,
        message: 'Deep link dispatched: ${info.strategyName}',
      );
    } else {
      _log(
        'Deep link dispatch FAILED: ${info.strategyName}',
        level: WalletLogLevel.warning,
        data: info.toMap(),
      );
    }
  }

  /// Log deep link return (critical for debugging callback issues)
  ///
  /// This is the MOST IMPORTANT logging point - it captures when
  /// the wallet app sends a callback to our app.
  void logDeepLinkReturn(Uri uri, {String? sourceApp}) {
    final returnInfo = DeepLinkReturnInfo.fromUri(uri, sourceApp: sourceApp);

    // Log even without active context - this is critical debugging info
    if (_context == null) {
      AppLogger.wallet(
        '*** DEEP LINK RETURN (no active connection) ***',
        data: returnInfo.toMap(),
      );
      return;
    }

    _context = _context!.copyWith(deepLinkReturn: returnInfo);

    // This is the missing log!
    _log(
      '***** APPROVAL CALLBACK RECEIVED *****',
      level: WalletLogLevel.info,
      data: returnInfo.toMap(),
    );

    // Add Sentry breadcrumb for this critical event
    SentryService.instance.addBreadcrumb(
      message: 'Deep link return received',
      category: 'wallet.deeplink.return',
      data: returnInfo.toMap(),
      level: SentryLevel.info,
    );

    _emitEvent(WalletLogEvent(
      type: WalletLogEventType.deepLinkReturn,
      deepLinkReturn: returnInfo,
      context: _context,
    ));
  }

  /// Log relay event
  void logRelayEvent(
    String eventType, {
    String? relayUrl,
    String? errorCode,
    String? errorMessage,
    bool isReconnection = false,
    int? attemptNumber,
  }) {
    final info = RelayEventInfo(
      eventType: eventType,
      relayUrl: relayUrl,
      errorCode: errorCode,
      errorMessage: errorMessage,
      isReconnection: isReconnection,
      attemptNumber: attemptNumber,
      timestamp: DateTime.now(),
    );

    _log(
      'Relay event: $eventType',
      level: errorCode != null ? WalletLogLevel.warning : WalletLogLevel.info,
      data: info.toMap(),
    );
  }

  /// Log session event
  void logSessionEvent(
    String eventType, {
    String? topic,
    String? peerName,
    List<String>? namespaces,
    int? accountCount,
    int? chainId,
    Map<String, dynamic>? extra,
  }) {
    final info = SessionEventInfo(
      eventType: eventType,
      topicHash: topic != null ? _redactTopic(topic) : null,
      peerName: peerName,
      namespaces: namespaces,
      accountCount: accountCount,
      chainId: chainId,
      timestamp: DateTime.now(),
      extra: extra,
    );

    _log(
      'Session event: $eventType',
      data: info.toMap(),
    );
  }

  /// Log error with structured context
  void logError({
    required String errorCode,
    required String message,
    String? errorClass,
    StackTrace? stackTrace,
    bool isFatal = false,
  }) {
    if (_context == null) {
      AppLogger.e('[WALLET] Error (no active connection): $message');
      return;
    }

    _context = _context!.copyWith(
      errorCode: errorCode,
      errorMessage: message,
      errorClass: errorClass,
    );

    // Determine which error step based on current state
    final errorStep = _determineErrorStep();
    transitionTo(errorStep, message: 'ERROR: $message');

    _log(
      'ERROR: $message',
      level: WalletLogLevel.error,
      data: {
        'errorCode': errorCode,
        if (errorClass != null) 'errorClass': errorClass,
      },
    );

    // Send to Sentry if fatal or important
    if (isFatal) {
      SentryService.instance.captureMessage(
        message,
        level: SentryLevel.error,
        extras: _context?.toLogPayload(),
        tags: {
          'wallet_type': _context?.walletType.name ?? 'unknown',
          'connection_step': _context?.step.name ?? 'unknown',
          'error_code': errorCode,
        },
      );
    }
  }

  // ============================================================================
  // Approval Timeout Detection
  // ============================================================================

  void _startApprovalTimeout() {
    _cancelApprovalTimeout();

    _log('Approval timeout started (${approvalTimeout.inSeconds}s)');

    _approvalTimeoutTimer = Timer(approvalTimeout, () {
      if (_context?.step == WalletConnectionStep.awaitingApproval) {
        _logApprovalTimeout();
      }
    });
  }

  void _cancelApprovalTimeout() {
    if (_approvalTimeoutTimer?.isActive ?? false) {
      _log('Approval timeout cancelled');
    }
    _approvalTimeoutTimer?.cancel();
    _approvalTimeoutTimer = null;
  }

  void _logApprovalTimeout() {
    if (_context == null) return;

    final diagnostics = ApprovalTimeoutDiagnostics(
      connectionId: _context!.connectionId,
      walletType: _context!.walletType.name,
      relayState: _context!.relayState.name,
      sessionState: _context!.sessionState.name,
      lifecycleState: _context!.lifecycleState?.name,
      isReconnecting: _context!.isReconnecting,
      deepLinkDispatched: _context!.deepLinkInfo?.launched ?? false,
      deepLinkReturnReceived: _context!.deepLinkReturn != null,
      elapsedMs: _context!.elapsedMs,
      timeoutMs: approvalTimeout.inMilliseconds,
      pendingRelayError: _context!.errorMessage,
    );

    _log(
      'APPROVAL TIMEOUT - No response received after ${approvalTimeout.inSeconds}s',
      level: WalletLogLevel.warning,
      data: diagnostics.toMap(),
    );

    transitionTo(
      WalletConnectionStep.approvalTimeout,
      message: 'Approval timeout after ${approvalTimeout.inSeconds}s',
    );

    // Send to Sentry as a warning (not error - user might just be slow)
    SentryService.instance.captureMessage(
      'Wallet approval timeout',
      level: SentryLevel.warning,
      extras: diagnostics.toMap(),
      tags: {
        'wallet_type': _context!.walletType.name,
        'relay_state': _context!.relayState.name,
        'deep_link_dispatched': (_context!.deepLinkInfo?.launched ?? false).toString(),
        'deep_link_returned': (_context!.deepLinkReturn != null).toString(),
      },
    );

    _emitEvent(WalletLogEvent(
      type: WalletLogEventType.approvalTimeout,
      context: _context,
      timeoutDiagnostics: diagnostics,
    ));
  }

  // ============================================================================
  // Private Logging Methods
  // ============================================================================

  void _logTransition(String message) {
    _log(message, isTransition: true);
  }

  void _log(
    String message, {
    WalletLogLevel level = WalletLogLevel.info,
    Map<String, dynamic>? data,
    bool isTransition = false,
  }) {
    // Build the log payload
    final payload = _context?.toLogPayload() ?? {};
    if (data != null) {
      payload.addAll(data);
    }

    // Format: [WALLET:shortId] step | message
    final prefix = _context != null
        ? '[WALLET:${_context!.shortId}]'
        : '[WALLET]';
    final stepPart = _context != null ? '${_context!.step.name} | ' : '';
    final formattedMessage = '$prefix $stepPart$message';

    // Log to AppLogger
    switch (level) {
      case WalletLogLevel.debug:
        AppLogger.d(formattedMessage);
      case WalletLogLevel.info:
        AppLogger.wallet(message, data: payload);
      case WalletLogLevel.warning:
        AppLogger.w(formattedMessage);
      case WalletLogLevel.error:
        AppLogger.e(formattedMessage);
    }

    // Add to DebugLogService for in-app viewing
    _addToDebugLog(message, level, payload);

    // Add Sentry breadcrumb
    _addSentryBreadcrumb(message, level, payload);
  }

  void _addToDebugLog(
    String message,
    WalletLogLevel level,
    Map<String, dynamic> payload,
  ) {
    final entry = WalletDebugLogEntry(
      id: '${_context?.connectionId ?? 'unknown'}-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      level: level.name,
      message: message,
      context: payload,
      connectionId: _context?.connectionId,
      walletType: _context?.walletType.name,
      step: _context?.step.name,
    );

    DebugLogService.instance.addWalletLog(entry);
  }

  void _addSentryBreadcrumb(
    String message,
    WalletLogLevel level,
    Map<String, dynamic> payload,
  ) {
    SentryService.instance.addBreadcrumb(
      message: message,
      category: 'wallet.connection',
      data: payload,
      level: _toSentryLevel(level),
    );
  }

  void _emitEvent(WalletLogEvent event) {
    _logStreamController.add(event);
  }

  WalletConnectionStep _determineErrorStep() {
    if (_context == null) return WalletConnectionStep.failed;

    return switch (_context!.step) {
      WalletConnectionStep.wcUriRequesting => WalletConnectionStep.failed,
      WalletConnectionStep.deeplinkDispatching => WalletConnectionStep.deeplinkError,
      WalletConnectionStep.awaitingApproval => WalletConnectionStep.sessionError,
      _ when _context!.relayState == RelayState.error => WalletConnectionStep.relayError,
      _ => WalletConnectionStep.failed,
    };
  }

  SentryLevel _toSentryLevel(WalletLogLevel level) => switch (level) {
    WalletLogLevel.debug => SentryLevel.debug,
    WalletLogLevel.info => SentryLevel.info,
    WalletLogLevel.warning => SentryLevel.warning,
    WalletLogLevel.error => SentryLevel.error,
  };

  String _redactTopic(String topic) {
    if (topic.length <= 10) return topic;
    return '${topic.substring(0, 6)}...${topic.substring(topic.length - 4)}';
  }

  /// Dispose resources
  void dispose() {
    _cleanup();
    _logStreamController.close();
  }
}

// ============================================================================
// Supporting Types
// ============================================================================

/// Type of wallet log event
enum WalletLogEventType {
  stateTransition,
  relayStateChange,
  sessionStateChange,
  deepLinkReturn,
  approvalTimeout,
}

/// Wallet log event for streaming
class WalletLogEvent {
  const WalletLogEvent({
    required this.type,
    this.step,
    this.previousStep,
    this.relayState,
    this.previousRelayState,
    this.sessionState,
    this.previousSessionState,
    this.deepLinkReturn,
    this.context,
    this.timeoutDiagnostics,
  });

  final WalletLogEventType type;
  final WalletConnectionStep? step;
  final WalletConnectionStep? previousStep;
  final RelayState? relayState;
  final RelayState? previousRelayState;
  final WcSessionState? sessionState;
  final WcSessionState? previousSessionState;
  final DeepLinkReturnInfo? deepLinkReturn;
  final WalletLogContext? context;
  final ApprovalTimeoutDiagnostics? timeoutDiagnostics;
}

/// Extended log entry for wallet-specific logs
class WalletDebugLogEntry extends DebugLogEntry {
  WalletDebugLogEntry({
    required super.id,
    required super.timestamp,
    required super.level,
    required this.message,
    required this.context,
    this.connectionId,
    this.walletType,
    this.step,
  }) : super(
          exceptionType: 'WalletLog',
          exceptionValue: message,
        );

  final String message;
  final Map<String, dynamic> context;
  final String? connectionId;
  final String? walletType;
  final String? step;

  @override
  String toString() {
    return 'WalletLog[$level] ${step ?? ''}: $message';
  }
}
