import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';

/// Session restoration phase enum
///
/// Represents the current phase of session restoration during app startup.
enum SessionRestorationPhase {
  /// App just started, not yet checked for sessions
  initial,

  /// Checking storage for persisted sessions
  checking,

  /// Actively restoring sessions (relay reconnection, etc.)
  restoring,

  /// Restoration finished (success or no sessions to restore)
  completed,

  /// Restoration failed with error
  failed,
}

/// Session restoration state
///
/// Tracks the progress and status of session restoration during app cold start.
class SessionRestorationState {
  const SessionRestorationState({
    this.phase = SessionRestorationPhase.initial,
    this.totalSessions = 0,
    this.restoredSessions = 0,
    this.currentWalletName,
    this.errorMessage,
    this.startedAt,
  });

  /// Current restoration phase
  final SessionRestorationPhase phase;

  /// Total number of sessions to restore
  final int totalSessions;

  /// Number of sessions successfully restored
  final int restoredSessions;

  /// Name of the wallet currently being restored
  final String? currentWalletName;

  /// Error message if restoration failed
  final String? errorMessage;

  /// When restoration started (for timeout tracking)
  final DateTime? startedAt;

  /// Whether restoration is in progress
  bool get isRestoring =>
      phase == SessionRestorationPhase.checking ||
      phase == SessionRestorationPhase.restoring;

  /// Whether restoration is complete (success or failure)
  bool get isComplete =>
      phase == SessionRestorationPhase.completed ||
      phase == SessionRestorationPhase.failed;

  /// Progress percentage (0.0 to 1.0)
  double get progress {
    if (totalSessions == 0) return 0.0;
    return restoredSessions / totalSessions;
  }

  /// Duration since restoration started
  Duration? get elapsed {
    if (startedAt == null) return null;
    return DateTime.now().difference(startedAt!);
  }

  /// Copy with modified fields
  SessionRestorationState copyWith({
    SessionRestorationPhase? phase,
    int? totalSessions,
    int? restoredSessions,
    String? currentWalletName,
    String? errorMessage,
    DateTime? startedAt,
    bool clearCurrentWallet = false,
    bool clearError = false,
  }) {
    return SessionRestorationState(
      phase: phase ?? this.phase,
      totalSessions: totalSessions ?? this.totalSessions,
      restoredSessions: restoredSessions ?? this.restoredSessions,
      currentWalletName:
          clearCurrentWallet ? null : (currentWalletName ?? this.currentWalletName),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      startedAt: startedAt ?? this.startedAt,
    );
  }

  @override
  String toString() {
    return 'SessionRestorationState('
        'phase: $phase, '
        'progress: $restoredSessions/$totalSessions, '
        'wallet: $currentWalletName'
        ')';
  }
}

/// Session restoration state notifier
///
/// Manages the session restoration lifecycle and provides updates
/// for UI components to react to restoration progress.
class SessionRestorationNotifier extends Notifier<SessionRestorationState> {
  @override
  SessionRestorationState build() {
    return const SessionRestorationState();
  }

  /// Start the restoration check phase
  void startChecking() {
    AppLogger.wallet('Session restoration: Starting check phase');
    state = SessionRestorationState(
      phase: SessionRestorationPhase.checking,
      startedAt: DateTime.now(),
    );
  }

  /// Begin restoring sessions with total count
  void beginRestoration({required int totalSessions}) {
    AppLogger.wallet('Session restoration: Beginning restoration', data: {
      'totalSessions': totalSessions,
    });
    state = state.copyWith(
      phase: SessionRestorationPhase.restoring,
      totalSessions: totalSessions,
      restoredSessions: 0,
    );
  }

  /// Update progress with current wallet being restored
  void updateProgress({
    required int restoredCount,
    String? currentWalletName,
  }) {
    AppLogger.wallet('Session restoration: Progress update', data: {
      'restored': restoredCount,
      'total': state.totalSessions,
      'currentWallet': currentWalletName,
    });
    state = state.copyWith(
      restoredSessions: restoredCount,
      currentWalletName: currentWalletName,
    );
  }

  /// Mark restoration as complete (success)
  void complete() {
    final elapsed = state.elapsed;
    AppLogger.wallet('Session restoration: Completed', data: {
      'restoredSessions': state.restoredSessions,
      'totalSessions': state.totalSessions,
      'elapsedMs': elapsed?.inMilliseconds,
    });
    state = state.copyWith(
      phase: SessionRestorationPhase.completed,
      clearCurrentWallet: true,
    );
  }

  /// Mark restoration as complete with no sessions found
  void completeNoSessions() {
    AppLogger.wallet('Session restoration: No sessions found');
    state = state.copyWith(
      phase: SessionRestorationPhase.completed,
      totalSessions: 0,
      restoredSessions: 0,
    );
  }

  /// Mark restoration as failed
  void fail(String error) {
    AppLogger.e('Session restoration: Failed', error);
    state = state.copyWith(
      phase: SessionRestorationPhase.failed,
      errorMessage: error,
      clearCurrentWallet: true,
    );
  }

  /// Skip restoration (user requested or timeout)
  void skip() {
    AppLogger.wallet('Session restoration: Skipped by user/timeout');
    state = state.copyWith(
      phase: SessionRestorationPhase.completed,
      clearCurrentWallet: true,
    );
  }

  /// Reset to initial state
  void reset() {
    state = const SessionRestorationState();
  }
}

/// Provider for session restoration state
final sessionRestorationProvider =
    NotifierProvider<SessionRestorationNotifier, SessionRestorationState>(
  SessionRestorationNotifier.new,
);

/// Provider for checking if sessions are currently being restored
///
/// Returns true during the checking and restoring phases.
/// UI components can use this to show loading states.
final isRestoringSessionsProvider = Provider<bool>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.isRestoring;
});

/// Provider for checking if app initialization (session restoration) is complete
///
/// Returns true when restoration is complete (success, failure, or no sessions).
/// UI components should wait for this before showing the main content.
final appInitializedProvider = Provider<bool>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.isComplete;
});

/// Provider for restoration progress (0.0 to 1.0)
final restorationProgressProvider = Provider<double>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.progress;
});

/// Provider for current restoration phase
final restorationPhaseProvider = Provider<SessionRestorationPhase>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.phase;
});

/// Provider for restoration error message
final restorationErrorProvider = Provider<String?>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.errorMessage;
});

/// Provider for current wallet name being restored
final currentRestoringWalletProvider = Provider<String?>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.currentWalletName;
});
