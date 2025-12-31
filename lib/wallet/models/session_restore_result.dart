import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';

/// Session Restoration Result
///
/// Provides detailed result of session restoration attempts including
/// status, wallet entity (if successful), and error details.
///
/// This allows callers to distinguish between different failure modes:
/// - Orphan sessions (topic not in SDK) should be removed immediately
/// - Relay disconnection may warrant a retry
/// - Invalid sessions need new connection
class SessionRestoreResult {
  const SessionRestoreResult._({
    required this.status,
    this.wallet,
    this.message,
    this.newTopic,
  });

  /// Creates a successful result
  factory SessionRestoreResult.success(
    WalletEntity wallet, {
    String? newTopic,
  }) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.success,
      wallet: wallet,
      newTopic: newTopic,
    );
  }

  /// Creates an orphan session result (topic not found in SDK)
  factory SessionRestoreResult.orphanSession(String message) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.topicNotFound,
      message: message,
    );
  }

  /// Creates a result for address-based fallback success
  factory SessionRestoreResult.addressFallbackSuccess(
    WalletEntity wallet,
    String newTopic,
  ) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.addressFallbackUsed,
      wallet: wallet,
      newTopic: newTopic,
    );
  }

  /// Creates a result for invalid session
  factory SessionRestoreResult.sessionInvalid(String message) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.sessionInvalid,
      message: message,
    );
  }

  /// Creates a result for relay disconnection
  factory SessionRestoreResult.relayDisconnected(String message) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.relayDisconnected,
      message: message,
    );
  }

  /// Creates a result for AppKit not ready
  factory SessionRestoreResult.appKitNotReady(String message) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.appKitNotReady,
      message: message,
    );
  }

  /// Creates a result for invalid topic format
  factory SessionRestoreResult.invalidTopicFormat(String message) {
    return SessionRestoreResult._(
      status: SessionRestoreStatus.invalidTopicFormat,
      message: message,
    );
  }

  /// The restoration status
  final SessionRestoreStatus status;

  /// The restored wallet entity (null if restoration failed)
  final WalletEntity? wallet;

  /// Human-readable message (typically for failed results)
  final String? message;

  /// New topic if session was found via fallback mechanisms
  /// This should be used to update the persisted session topic
  final String? newTopic;

  /// Whether this is an orphan session that should be removed from storage
  ///
  /// Orphan sessions occur when the app's local storage has a topic
  /// that no longer exists in the WalletConnect SDK.
  /// These should be removed immediately without retry.
  bool get isOrphanSession => status == SessionRestoreStatus.topicNotFound;

  /// Whether this failure should trigger a retry attempt
  ///
  /// Only relay disconnection warrants retries, as it may be a temporary
  /// network issue. Other failures indicate the session is gone.
  bool get shouldRetry => status == SessionRestoreStatus.relayDisconnected;

  /// Whether restoration was successful
  bool get isSuccess =>
      status == SessionRestoreStatus.success ||
      status == SessionRestoreStatus.addressFallbackUsed;

  /// Whether the topic changed (found via fallback)
  bool get topicChanged => newTopic != null && isSuccess;

  @override
  String toString() {
    if (isSuccess) {
      return 'SessionRestoreResult(success, wallet: ${wallet?.address}, newTopic: $newTopic)';
    }
    return 'SessionRestoreResult($status, message: $message)';
  }
}

/// Types of session restoration statuses
enum SessionRestoreStatus {
  /// Session restored successfully
  success,

  /// Topic not found in SDK (orphan session - should be removed)
  topicNotFound,

  /// Session found via address fallback (topic changed)
  addressFallbackUsed,

  /// Session found but invalid/expired
  sessionInvalid,

  /// Relay not connected (retry may help)
  relayDisconnected,

  /// AppKit not initialized
  appKitNotReady,

  /// Topic format is invalid
  invalidTopicFormat,
}

/// Extension for SessionRestoreStatus
extension SessionRestoreStatusExtension on SessionRestoreStatus {
  /// Get user-friendly description of the status
  String get description {
    switch (this) {
      case SessionRestoreStatus.success:
        return '세션 복원 성공';
      case SessionRestoreStatus.topicNotFound:
        return '세션이 SDK에 존재하지 않습니다 (만료됨)';
      case SessionRestoreStatus.addressFallbackUsed:
        return '주소 기반으로 세션을 찾았습니다';
      case SessionRestoreStatus.sessionInvalid:
        return '세션이 유효하지 않습니다';
      case SessionRestoreStatus.relayDisconnected:
        return 'Relay 연결이 끊어졌습니다';
      case SessionRestoreStatus.appKitNotReady:
        return 'AppKit이 초기화되지 않았습니다';
      case SessionRestoreStatus.invalidTopicFormat:
        return '토픽 형식이 유효하지 않습니다';
    }
  }
}
