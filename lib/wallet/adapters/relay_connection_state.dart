import 'dart:async';

import 'package:wallet_integration_practice/core/utils/logger.dart';

/// Relay connection state machine for WalletConnect
///
/// This state machine prevents race conditions by enforcing valid state
/// transitions and using a lock to prevent concurrent state changes.
///
/// Valid state transitions:
/// ```
/// disconnected → connecting | reconnecting
/// connecting → connected | error | disconnected
/// connected → disconnecting | reconnecting | error
/// disconnecting → disconnected | error
/// reconnecting → connected | disconnected | error
/// error → connecting | disconnected
/// ```
enum RelayConnectionState {
  /// Not connected to relay
  disconnected,

  /// Currently disconnecting from relay
  disconnecting,

  /// Currently connecting to relay
  connecting,

  /// Successfully connected to relay
  connected,

  /// Currently reconnecting to relay (disconnect + connect cycle)
  reconnecting,

  /// Error state (can recover by connecting or disconnecting)
  error,
}

/// State machine that manages relay connection state transitions
///
/// Provides thread-safe state transitions and prevents invalid state changes.
/// Use [tryTransition] to attempt a state transition - it will return false
/// if the transition is not allowed from the current state.
class RelayConnectionStateMachine {
  RelayConnectionStateMachine();

  /// Current state
  RelayConnectionState _state = RelayConnectionState.disconnected;

  /// Lock to prevent concurrent state transitions
  final _transitionLock = _AsyncLock();

  /// Stream controller for state changes
  final _stateController = StreamController<RelayConnectionState>.broadcast();

  /// Get current state
  RelayConnectionState get state => _state;

  /// Stream of state changes
  Stream<RelayConnectionState> get stateStream => _stateController.stream;

  /// Whether currently in a connected state
  bool get isConnected => _state == RelayConnectionState.connected;

  /// Whether currently in any transition state
  bool get isTransitioning =>
      _state == RelayConnectionState.connecting ||
      _state == RelayConnectionState.disconnecting ||
      _state == RelayConnectionState.reconnecting;

  /// Attempt state transition with validation
  ///
  /// Returns true if transition was allowed and executed, false otherwise.
  /// This method is thread-safe and prevents concurrent transitions.
  Future<bool> tryTransition(RelayConnectionState newState) async {
    return _transitionLock.synchronized(() async {
      final allowed = _isTransitionAllowed(_state, newState);

      if (allowed) {
        final oldState = _state;
        _state = newState;
        _stateController.add(newState);

        AppLogger.wallet('Relay state transition', data: {
          'from': oldState.name,
          'to': newState.name,
        });
      } else {
        AppLogger.wallet('Relay state transition BLOCKED', data: {
          'current': _state.name,
          'attempted': newState.name,
        });
      }

      return allowed;
    });
  }

  /// Force state change without validation (for emergency recovery)
  ///
  /// Use this only when you need to recover from an unknown state.
  /// Prefer [tryTransition] for normal operations.
  Future<void> forceState(RelayConnectionState newState) async {
    await _transitionLock.synchronized(() async {
      final oldState = _state;
      _state = newState;
      _stateController.add(newState);

      AppLogger.wallet('Relay state FORCED', data: {
        'from': oldState.name,
        'to': newState.name,
      });
    });
  }

  /// Reset to disconnected state
  Future<void> reset() async {
    await forceState(RelayConnectionState.disconnected);
  }

  /// Check if a transition from [current] to [next] is allowed
  bool _isTransitionAllowed(
    RelayConnectionState current,
    RelayConnectionState next,
  ) {
    // Same state transition is always a no-op (but allowed)
    if (current == next) return true;

    switch (current) {
      case RelayConnectionState.disconnected:
        // From disconnected, can start connecting or reconnecting (for cold-start session restoration)
        return next == RelayConnectionState.connecting ||
            next == RelayConnectionState.reconnecting;

      case RelayConnectionState.connecting:
        // From connecting, can complete to connected, fail to error, or cancel to disconnected
        return next == RelayConnectionState.connected ||
            next == RelayConnectionState.error ||
            next == RelayConnectionState.disconnected;

      case RelayConnectionState.connected:
        // From connected, can start disconnecting, start reconnecting, or fail to error
        return next == RelayConnectionState.disconnecting ||
            next == RelayConnectionState.reconnecting ||
            next == RelayConnectionState.error;

      case RelayConnectionState.disconnecting:
        // From disconnecting, can complete to disconnected or fail to error
        return next == RelayConnectionState.disconnected ||
            next == RelayConnectionState.error;

      case RelayConnectionState.reconnecting:
        // From reconnecting, can complete to connected, fail to disconnected, or fail to error
        return next == RelayConnectionState.connected ||
            next == RelayConnectionState.disconnected ||
            next == RelayConnectionState.error;

      case RelayConnectionState.error:
        // From error, can try connecting again or fully disconnect
        return next == RelayConnectionState.connecting ||
            next == RelayConnectionState.disconnected;
    }
  }

  /// Dispose resources
  void dispose() {
    _stateController.close();
  }
}

/// Simple async mutex lock for thread-safe operations
///
/// Ensures only one operation can execute at a time within the synchronized block.
class _AsyncLock {
  Completer<void>? _completer;

  /// Execute [fn] with exclusive access
  ///
  /// If another operation is already executing, waits for it to complete.
  Future<T> synchronized<T>(Future<T> Function() fn) async {
    // Wait for any existing operation to complete
    while (_completer != null) {
      await _completer!.future;
    }

    // Acquire lock
    _completer = Completer<void>();

    try {
      return await fn();
    } finally {
      // Release lock
      _completer!.complete();
      _completer = null;
    }
  }
}
