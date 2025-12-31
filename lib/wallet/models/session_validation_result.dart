/// Session Validation Result
///
/// Provides detailed result of session validity check including
/// validation status and error details when invalid.
class SessionValidationResult {
  const SessionValidationResult._({
    required this.isValid,
    this.status = SessionValidationStatus.valid,
    this.message,
  });

  /// Creates a valid result
  factory SessionValidationResult.valid() {
    return const SessionValidationResult._(
      isValid: true,
      status: SessionValidationStatus.valid,
    );
  }

  /// Creates an invalid result with status and message
  factory SessionValidationResult.invalid(
    SessionValidationStatus status,
    String message,
  ) {
    return SessionValidationResult._(
      isValid: false,
      status: status,
      message: message,
    );
  }

  /// Whether the session is valid
  final bool isValid;

  /// Validation status indicating the specific validation result
  final SessionValidationStatus status;

  /// Human-readable message (typically for invalid results)
  final String? message;

  /// Check if the validation failure is recoverable
  ///
  /// Recoverable failures can potentially be fixed by reconnecting
  /// or waiting for relay connectivity.
  bool get isRecoverable {
    switch (status) {
      case SessionValidationStatus.valid:
        return true;
      case SessionValidationStatus.relayDisconnected:
        return true; // May reconnect
      case SessionValidationStatus.sessionExpired:
        return false; // Need new session
      case SessionValidationStatus.noAccounts:
        return false; // Need new session
      case SessionValidationStatus.invalidNamespace:
        return false; // Need new session
      case SessionValidationStatus.encryptionKeyInvalid:
        return false; // Need new session
      case SessionValidationStatus.walletMismatch:
        return false; // Need new session
      case SessionValidationStatus.sessionNotFound:
        return false; // Need new session
    }
  }

  @override
  String toString() {
    if (isValid) {
      return 'SessionValidationResult(valid)';
    }
    return 'SessionValidationResult(invalid: $status, message: $message)';
  }
}

/// Types of session validation statuses
enum SessionValidationStatus {
  /// Session is valid
  valid,

  /// Relay is not connected (may be temporary)
  relayDisconnected,

  /// Session has expired
  sessionExpired,

  /// Session has no accounts
  noAccounts,

  /// Session namespace is invalid or missing
  invalidNamespace,

  /// Encryption keys are invalid (Phantom specific)
  encryptionKeyInvalid,

  /// Connected wallet doesn't match expected type
  walletMismatch,

  /// Session not found in AppKit/storage
  sessionNotFound,
}

/// Extension for SessionValidationStatus
extension SessionValidationStatusExtension on SessionValidationStatus {
  /// Get user-friendly description of the status
  String get description {
    switch (this) {
      case SessionValidationStatus.valid:
        return '유효한 세션';
      case SessionValidationStatus.relayDisconnected:
        return 'Relay 연결이 끊어졌습니다';
      case SessionValidationStatus.sessionExpired:
        return '세션이 만료되었습니다';
      case SessionValidationStatus.noAccounts:
        return '연결된 계정이 없습니다';
      case SessionValidationStatus.invalidNamespace:
        return '유효하지 않은 네임스페이스';
      case SessionValidationStatus.encryptionKeyInvalid:
        return '암호화 키가 유효하지 않습니다';
      case SessionValidationStatus.walletMismatch:
        return '지갑 유형이 일치하지 않습니다';
      case SessionValidationStatus.sessionNotFound:
        return '세션을 찾을 수 없습니다';
    }
  }
}
