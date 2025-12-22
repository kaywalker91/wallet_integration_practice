/// Wallet connection logging state machine enums
///
/// These enums define the complete state machine for tracking
/// wallet connection flow from start to completion or failure.
library;

/// Represents the complete connection flow state machine
///
/// Each step corresponds to a distinct phase in the wallet connection process.
/// Transitions should be logged to enable debugging of connection issues.
enum WalletConnectionStep {
  // Initial states
  /// No connection in progress
  idle,

  /// Connection process has started
  starting,

  // WalletConnect URI generation
  /// Requesting WC URI from relay
  wcUriRequesting,

  /// WC URI successfully generated
  wcUriReceived,

  // Deep link dispatch
  /// Attempting to open wallet app via deep link
  deeplinkDispatching,

  /// Deep link successfully dispatched (wallet app opened)
  deeplinkDispatched,

  // Approval waiting
  /// Waiting for user approval in wallet app
  awaitingApproval,

  // Approval results
  /// User approved the connection in wallet
  approvalReceived,

  /// User rejected the connection in wallet
  approvalRejected,

  /// No response received within timeout period
  approvalTimeout,

  // Session establishment
  /// Session is being established after approval
  sessionEstablishing,

  /// Session successfully established
  sessionEstablished,

  // Error states
  /// Relay connection error occurred
  relayError,

  /// Deep link dispatch failed
  deeplinkError,

  /// Session error occurred
  sessionError,

  /// Generic failure state
  failed,
}

/// WalletConnect relay connection state
enum RelayState {
  /// Not connected to relay
  disconnected,

  /// Establishing connection to relay
  connecting,

  /// Successfully connected to relay
  connected,

  /// Attempting to reconnect after disconnection
  reconnecting,

  /// Relay connection error
  error,
}

/// WalletConnect session state
enum WcSessionState {
  /// No session exists
  none,

  /// Session has been proposed
  proposed,

  /// Session was approved by user
  approved,

  /// Session was rejected by user
  rejected,

  /// Session was deleted
  deleted,

  /// Session error occurred
  error,
}

/// Log severity level
enum WalletLogLevel {
  /// Debug information
  debug,

  /// Informational messages
  info,

  /// Warning messages
  warning,

  /// Error messages
  error,
}

/// Extension to provide display names for WalletConnectionStep
extension WalletConnectionStepX on WalletConnectionStep {
  /// Human-readable display name for this step
  String get displayName {
    return switch (this) {
      WalletConnectionStep.idle => 'Idle',
      WalletConnectionStep.starting => 'Starting',
      WalletConnectionStep.wcUriRequesting => 'Requesting URI',
      WalletConnectionStep.wcUriReceived => 'URI Received',
      WalletConnectionStep.deeplinkDispatching => 'Opening Wallet',
      WalletConnectionStep.deeplinkDispatched => 'Wallet Opened',
      WalletConnectionStep.awaitingApproval => 'Awaiting Approval',
      WalletConnectionStep.approvalReceived => 'Approved',
      WalletConnectionStep.approvalRejected => 'Rejected',
      WalletConnectionStep.approvalTimeout => 'Timeout',
      WalletConnectionStep.sessionEstablishing => 'Establishing Session',
      WalletConnectionStep.sessionEstablished => 'Connected',
      WalletConnectionStep.relayError => 'Relay Error',
      WalletConnectionStep.deeplinkError => 'Deep Link Error',
      WalletConnectionStep.sessionError => 'Session Error',
      WalletConnectionStep.failed => 'Failed',
    };
  }

  /// Whether this step represents an error state
  bool get isError {
    return switch (this) {
      WalletConnectionStep.relayError ||
      WalletConnectionStep.deeplinkError ||
      WalletConnectionStep.sessionError ||
      WalletConnectionStep.failed ||
      WalletConnectionStep.approvalRejected ||
      WalletConnectionStep.approvalTimeout =>
        true,
      _ => false,
    };
  }

  /// Whether this step represents a successful completion
  bool get isSuccess => this == WalletConnectionStep.sessionEstablished;

  /// Whether this step represents an in-progress state
  bool get isInProgress {
    return switch (this) {
      WalletConnectionStep.starting ||
      WalletConnectionStep.wcUriRequesting ||
      WalletConnectionStep.wcUriReceived ||
      WalletConnectionStep.deeplinkDispatching ||
      WalletConnectionStep.deeplinkDispatched ||
      WalletConnectionStep.awaitingApproval ||
      WalletConnectionStep.approvalReceived ||
      WalletConnectionStep.sessionEstablishing =>
        true,
      _ => false,
    };
  }
}

/// Extension to provide display names for RelayState
extension RelayStateX on RelayState {
  /// Human-readable display name for this state
  String get displayName {
    return switch (this) {
      RelayState.disconnected => 'Disconnected',
      RelayState.connecting => 'Connecting',
      RelayState.connected => 'Connected',
      RelayState.reconnecting => 'Reconnecting',
      RelayState.error => 'Error',
    };
  }
}

/// Extension to provide display names for WcSessionState
extension WcSessionStateX on WcSessionState {
  /// Human-readable display name for this state
  String get displayName {
    return switch (this) {
      WcSessionState.none => 'None',
      WcSessionState.proposed => 'Proposed',
      WcSessionState.approved => 'Approved',
      WcSessionState.rejected => 'Rejected',
      WcSessionState.deleted => 'Deleted',
      WcSessionState.error => 'Error',
    };
  }
}
