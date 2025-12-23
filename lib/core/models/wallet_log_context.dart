import 'package:flutter/widgets.dart';

import '../constants/wallet_constants.dart';
import 'wallet_log_enums.dart';
import 'wallet_log_models.dart';

/// Holds all common context fields for wallet connection logging
///
/// This immutable class captures the complete state of a wallet connection
/// attempt at any given point in time. It is used to provide consistent
/// context across all log entries during a connection flow.
///
/// Example usage:
/// ```dart
/// final context = WalletLogContext.start(
///   walletType: WalletType.metamask,
///   chainId: 1,
/// );
///
/// // Later, transition to a new step
/// final updated = context.transitionTo(WalletConnectionStep.wcUriReceived);
/// ```
class WalletLogContext {
  const WalletLogContext({
    required this.connectionId,
    required this.walletType,
    this.chainId,
    this.cluster,
    required this.step,
    this.previousStep,
    this.lifecycleState,
    required this.relayState,
    this.isReconnecting = false,
    required this.sessionState,
    this.sessionTopic,
    this.peerName,
    this.attempt = 0,
    this.maxRetries = 3,
    this.errorCode,
    this.errorMessage,
    this.errorClass,
    required this.startedAt,
    this.deepLinkInfo,
    this.deepLinkReturn,
    this.wcUriInfo,
  });

  /// Create a new context for starting a connection
  factory WalletLogContext.start({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) {
    return WalletLogContext(
      connectionId: generateConnectionId(walletType),
      walletType: walletType,
      chainId: chainId,
      cluster: cluster,
      step: WalletConnectionStep.starting,
      relayState: RelayState.disconnected,
      sessionState: WcSessionState.none,
      startedAt: DateTime.now(),
    );
  }

  // ===== Connection Identity =====

  /// Unique ID per connection attempt
  ///
  /// Format: "walletType-timestamp"
  /// Example: "metamask-20250213T132337Z"
  final String connectionId;

  /// The wallet type being connected
  final WalletType walletType;

  /// Target chain ID for EVM wallets
  final int? chainId;

  /// Target cluster for Solana wallets (mainnet-beta, devnet, testnet)
  final String? cluster;

  // ===== State Machine =====

  /// Current step in the connection flow
  final WalletConnectionStep step;

  /// Previous step (for transition logging)
  final WalletConnectionStep? previousStep;

  // ===== Lifecycle State =====

  /// Current app lifecycle state
  final AppLifecycleState? lifecycleState;

  // ===== Relay State =====

  /// Current WalletConnect relay state
  final RelayState relayState;

  /// Whether relay reconnection is in progress
  final bool isReconnecting;

  // ===== Session State =====

  /// Current WC session state
  final WcSessionState sessionState;

  /// Session topic (when available, redacted)
  final String? sessionTopic;

  /// Peer wallet metadata name
  final String? peerName;

  // ===== Retry & Attempt Info =====

  /// Current retry attempt number (0-based)
  final int attempt;

  /// Maximum allowed retries
  final int maxRetries;

  // ===== Error Info =====

  /// Error code if in error state
  final String? errorCode;

  /// Error message if in error state
  final String? errorMessage;

  /// Error class name for categorization
  final String? errorClass;

  // ===== Timing =====

  /// When this connection attempt started
  final DateTime startedAt;

  // ===== Deep Link Info =====

  /// Last deep link dispatch result
  final DeepLinkDispatchInfo? deepLinkInfo;

  /// Last incoming deep link
  final DeepLinkReturnInfo? deepLinkReturn;

  // ===== WC URI Info =====

  /// WC URI metadata (security-redacted)
  final WcUriInfo? wcUriInfo;

  /// Duration since start
  Duration get elapsed => DateTime.now().difference(startedAt);

  /// Elapsed time in milliseconds
  int get elapsedMs => elapsed.inMilliseconds;

  /// Generate a unique connection ID
  ///
  /// Format: walletType-YYYYMMDDTHHMMSSZ
  static String generateConnectionId(WalletType walletType) {
    final now = DateTime.now().toUtc();
    final timestamp =
        now.toIso8601String().replaceAll(RegExp(r'[:\-\.]'), '').split('T').join('T').substring(0, 15);
    return '${walletType.name}-$timestamp';
  }

  /// Create a copy with updated fields
  WalletLogContext copyWith({
    String? connectionId,
    WalletType? walletType,
    int? chainId,
    String? cluster,
    WalletConnectionStep? step,
    WalletConnectionStep? previousStep,
    AppLifecycleState? lifecycleState,
    RelayState? relayState,
    bool? isReconnecting,
    WcSessionState? sessionState,
    String? sessionTopic,
    String? peerName,
    int? attempt,
    int? maxRetries,
    String? errorCode,
    String? errorMessage,
    String? errorClass,
    DateTime? startedAt,
    DeepLinkDispatchInfo? deepLinkInfo,
    DeepLinkReturnInfo? deepLinkReturn,
    WcUriInfo? wcUriInfo,
    bool clearError = false,
    bool clearDeepLinkReturn = false,
  }) {
    return WalletLogContext(
      connectionId: connectionId ?? this.connectionId,
      walletType: walletType ?? this.walletType,
      chainId: chainId ?? this.chainId,
      cluster: cluster ?? this.cluster,
      step: step ?? this.step,
      previousStep: previousStep ?? this.previousStep,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      relayState: relayState ?? this.relayState,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      sessionState: sessionState ?? this.sessionState,
      sessionTopic: sessionTopic ?? this.sessionTopic,
      peerName: peerName ?? this.peerName,
      attempt: attempt ?? this.attempt,
      maxRetries: maxRetries ?? this.maxRetries,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorClass: clearError ? null : (errorClass ?? this.errorClass),
      startedAt: startedAt ?? this.startedAt,
      deepLinkInfo: deepLinkInfo ?? this.deepLinkInfo,
      deepLinkReturn:
          clearDeepLinkReturn ? null : (deepLinkReturn ?? this.deepLinkReturn),
      wcUriInfo: wcUriInfo ?? this.wcUriInfo,
    );
  }

  /// Transition to a new step, preserving previous step
  WalletLogContext transitionTo(WalletConnectionStep newStep) {
    return copyWith(
      previousStep: step,
      step: newStep,
    );
  }

  /// Increment attempt counter
  WalletLogContext nextAttempt() {
    return copyWith(
      attempt: attempt + 1,
      clearError: true,
    );
  }

  /// Convert to structured map for logging
  ///
  /// This map can be serialized to JSON and used for structured logging.
  Map<String, dynamic> toLogPayload() {
    return {
      'connectionId': connectionId,
      'walletType': walletType.name,
      if (chainId != null) 'chainId': chainId,
      if (cluster != null) 'cluster': cluster,
      'step': step.name,
      if (previousStep != null) 'previousStep': previousStep!.name,
      if (lifecycleState != null) 'lifecycleState': lifecycleState!.name,
      'relayState': relayState.name,
      if (isReconnecting) 'isReconnecting': isReconnecting,
      'sessionState': sessionState.name,
      if (sessionTopic != null) 'sessionTopic': _redactTopic(sessionTopic!),
      if (peerName != null) 'peerName': peerName,
      'attempt': attempt,
      if (attempt > 0) 'maxRetries': maxRetries,
      if (errorCode != null) 'errorCode': errorCode,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (errorClass != null) 'errorClass': errorClass,
      'elapsedMs': elapsedMs,
      if (deepLinkInfo != null) 'deepLink': deepLinkInfo!.toMap(),
      if (deepLinkReturn != null) 'deepLinkReturn': deepLinkReturn!.toMap(),
      if (wcUriInfo != null) 'wcUri': wcUriInfo!.toMap(),
    };
  }

  /// Get a short ID suffix for log prefixes
  ///
  /// Example: "T132337Z" from "metamask-20250213T132337Z"
  String get shortId {
    final parts = connectionId.split('-');
    if (parts.length >= 2) {
      final timestamp = parts.sublist(1).join('-');
      // Return just the time portion: THHMMSSZ
      if (timestamp.contains('T')) {
        return timestamp.substring(timestamp.indexOf('T'));
      }
    }
    return connectionId.length > 10
        ? connectionId.substring(connectionId.length - 10)
        : connectionId;
  }

  /// Redact a topic for safe logging
  String _redactTopic(String topic) {
    if (topic.length <= 10) return topic;
    return '${topic.substring(0, 6)}...${topic.substring(topic.length - 4)}';
  }

  @override
  String toString() {
    return 'WalletLogContext($connectionId, step: ${step.name}, relay: ${relayState.name}, session: ${sessionState.name})';
  }
}
