/// Session validation result enum
///
/// Represents the outcome of a session validation check.
enum SessionValidationStatus {
  /// Session is valid and can be used
  valid,

  /// Session has expired and needs re-authentication
  expired,

  /// Session topic is invalid or not found
  invalidTopic,

  /// Relay connection failed
  relayDisconnected,

  /// Network is not available
  networkOffline,

  /// Session permissions have been revoked
  permissionsRevoked,

  /// Unknown validation error
  unknown,
}

/// Session validation result with details
class SessionValidationResult {
  const SessionValidationResult({
    required this.status,
    this.message,
    this.sessionTopic,
    this.walletType,
  });

  /// Create a valid result
  factory SessionValidationResult.valid({
    String? sessionTopic,
    String? walletType,
  }) {
    return SessionValidationResult(
      status: SessionValidationStatus.valid,
      sessionTopic: sessionTopic,
      walletType: walletType,
    );
  }

  /// Create an expired result
  factory SessionValidationResult.expired({
    String? sessionTopic,
    String? walletType,
  }) {
    return SessionValidationResult(
      status: SessionValidationStatus.expired,
      message: 'Session has expired. Please reconnect your wallet.',
      sessionTopic: sessionTopic,
      walletType: walletType,
    );
  }

  /// Create a relay disconnected result
  factory SessionValidationResult.relayDisconnected({
    String? sessionTopic,
    String? walletType,
  }) {
    return SessionValidationResult(
      status: SessionValidationStatus.relayDisconnected,
      message: 'Unable to connect to relay server. Please check your connection.',
      sessionTopic: sessionTopic,
      walletType: walletType,
    );
  }

  /// Create a network offline result
  factory SessionValidationResult.networkOffline({
    String? sessionTopic,
    String? walletType,
  }) {
    return SessionValidationResult(
      status: SessionValidationStatus.networkOffline,
      message: 'Device is offline. Session will be restored when connected.',
      sessionTopic: sessionTopic,
      walletType: walletType,
    );
  }

  /// Create an invalid topic result
  factory SessionValidationResult.invalidTopic({
    String? sessionTopic,
    String? walletType,
  }) {
    return SessionValidationResult(
      status: SessionValidationStatus.invalidTopic,
      message: 'Session is no longer valid. Please reconnect your wallet.',
      sessionTopic: sessionTopic,
      walletType: walletType,
    );
  }

  /// Create an unknown error result
  factory SessionValidationResult.unknown({
    String? message,
    String? sessionTopic,
    String? walletType,
  }) {
    return SessionValidationResult(
      status: SessionValidationStatus.unknown,
      message: message ?? 'An unknown error occurred during session validation.',
      sessionTopic: sessionTopic,
      walletType: walletType,
    );
  }

  /// Validation status
  final SessionValidationStatus status;

  /// Human-readable error message
  final String? message;

  /// Session topic (for WalletConnect sessions)
  final String? sessionTopic;

  /// Wallet type name
  final String? walletType;

  /// Whether the session is valid
  bool get isValid => status == SessionValidationStatus.valid;

  /// Whether the session can be retried (network issue)
  bool get isRetryable =>
      status == SessionValidationStatus.relayDisconnected ||
      status == SessionValidationStatus.networkOffline;

  /// Whether the session needs re-authentication
  bool get needsReauth =>
      status == SessionValidationStatus.expired ||
      status == SessionValidationStatus.invalidTopic ||
      status == SessionValidationStatus.permissionsRevoked;

  @override
  String toString() {
    return 'SessionValidationResult(status: $status, message: $message)';
  }
}
