import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';

/// Individual wallet restoration status
enum WalletRestorationStatus {
  /// Waiting to be restored
  pending,

  /// Currently being restored
  restoring,

  /// Successfully restored
  success,

  /// Failed to restore
  failed,

  /// Skipped (user requested or timeout)
  skipped,
}

/// Individual wallet restoration info for UI display
class WalletRestorationInfo {
  const WalletRestorationInfo({
    required this.walletId,
    required this.walletName,
    required this.walletType,
    this.status = WalletRestorationStatus.pending,
    this.errorMessage,
    this.iconPath,
  });

  /// Unique identifier for this wallet session
  final String walletId;

  /// Display name for the wallet (e.g., "MetaMask", "Phantom")
  final String walletName;

  /// Type of wallet (for icon selection)
  final String walletType;

  /// Current restoration status
  final WalletRestorationStatus status;

  /// Error message if restoration failed
  final String? errorMessage;

  /// Optional icon path for the wallet
  final String? iconPath;

  /// Whether this wallet is currently being processed
  bool get isProcessing => status == WalletRestorationStatus.restoring;

  /// Whether this wallet's restoration is complete (success or failure)
  bool get isComplete =>
      status == WalletRestorationStatus.success ||
      status == WalletRestorationStatus.failed ||
      status == WalletRestorationStatus.skipped;

  /// Create a copy with updated fields
  WalletRestorationInfo copyWith({
    WalletRestorationStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return WalletRestorationInfo(
      walletId: walletId,
      walletName: walletName,
      walletType: walletType,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      iconPath: iconPath,
    );
  }

  @override
  String toString() {
    return 'WalletRestorationInfo(id: $walletId, name: $walletName, status: $status)';
  }
}

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

  /// Restoration timed out (partial success possible)
  timedOut,
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
    this.isOffline = false,
    this.wallets = const [],
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

  /// Whether device is offline (no network connectivity)
  final bool isOffline;

  /// List of individual wallet restoration info for per-wallet status display
  final List<WalletRestorationInfo> wallets;

  /// Whether restoration is in progress
  bool get isRestoring =>
      phase == SessionRestorationPhase.checking ||
      phase == SessionRestorationPhase.restoring;

  /// Whether restoration is complete (success, failure, or timeout)
  bool get isComplete =>
      phase == SessionRestorationPhase.completed ||
      phase == SessionRestorationPhase.failed ||
      phase == SessionRestorationPhase.timedOut;

  /// Whether restoration timed out
  bool get isTimedOut => phase == SessionRestorationPhase.timedOut;

  /// Whether partial restoration succeeded (some sessions restored before timeout)
  bool get hasPartialSuccess =>
      phase == SessionRestorationPhase.timedOut && restoredSessions > 0;

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

  /// Number of wallets that failed to restore
  int get failedCount =>
      wallets.where((w) => w.status == WalletRestorationStatus.failed).length;

  /// Number of wallets that are still pending
  int get pendingCount =>
      wallets.where((w) => w.status == WalletRestorationStatus.pending).length;

  /// Whether any wallet failed to restore
  bool get hasFailures => failedCount > 0;

  /// Get wallet info by ID
  WalletRestorationInfo? getWalletById(String walletId) {
    try {
      return wallets.firstWhere((w) => w.walletId == walletId);
    } catch (_) {
      return null;
    }
  }

  /// Copy with modified fields
  SessionRestorationState copyWith({
    SessionRestorationPhase? phase,
    int? totalSessions,
    int? restoredSessions,
    String? currentWalletName,
    String? errorMessage,
    DateTime? startedAt,
    bool? isOffline,
    List<WalletRestorationInfo>? wallets,
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
      isOffline: isOffline ?? this.isOffline,
      wallets: wallets ?? this.wallets,
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

  /// Begin restoring sessions with total count and wallet list
  void beginRestoration({
    required int totalSessions,
    List<WalletRestorationInfo>? wallets,
  }) {
    AppLogger.wallet('Session restoration: Beginning restoration', data: {
      'totalSessions': totalSessions,
      'walletCount': wallets?.length ?? 0,
    });
    state = state.copyWith(
      phase: SessionRestorationPhase.restoring,
      totalSessions: totalSessions,
      restoredSessions: 0,
      wallets: wallets ?? [],
    );
  }

  /// Initialize the wallet list for restoration
  void initWallets(List<WalletRestorationInfo> wallets) {
    AppLogger.wallet('Session restoration: Initializing wallets', data: {
      'count': wallets.length,
      'wallets': wallets.map((w) => w.walletName).toList(),
    });
    state = state.copyWith(
      wallets: wallets,
      totalSessions: wallets.length,
    );
  }

  /// Update individual wallet status
  void updateWalletStatus({
    required String walletId,
    required WalletRestorationStatus status,
    String? errorMessage,
  }) {
    final updatedWallets = state.wallets.map((wallet) {
      if (wallet.walletId == walletId) {
        return wallet.copyWith(
          status: status,
          errorMessage: errorMessage,
        );
      }
      return wallet;
    }).toList();

    // Calculate new restored count based on successful wallets
    final restoredCount = updatedWallets
        .where((w) => w.status == WalletRestorationStatus.success)
        .length;

    // Get current wallet name if it's being restored
    final currentWallet = updatedWallets
        .cast<WalletRestorationInfo?>()
        .firstWhere(
          (w) => w?.status == WalletRestorationStatus.restoring,
          orElse: () => null,
        );

    AppLogger.wallet('Session restoration: Wallet status updated', data: {
      'walletId': walletId,
      'status': status.name,
      'restoredCount': restoredCount,
      'error': errorMessage,
    });

    state = state.copyWith(
      wallets: updatedWallets,
      restoredSessions: restoredCount,
      currentWalletName: currentWallet?.walletName,
    );
  }

  /// Mark a wallet as currently being restored
  void startWalletRestoration(String walletId) {
    updateWalletStatus(
      walletId: walletId,
      status: WalletRestorationStatus.restoring,
    );
  }

  /// Mark a wallet as successfully restored
  void walletRestorationSuccess(String walletId) {
    updateWalletStatus(
      walletId: walletId,
      status: WalletRestorationStatus.success,
    );
  }

  /// Mark a wallet as failed to restore
  void walletRestorationFailed(String walletId, String error) {
    updateWalletStatus(
      walletId: walletId,
      status: WalletRestorationStatus.failed,
      errorMessage: error,
    );
  }

  /// Retry restoration for a specific wallet
  void retryWallet(String walletId) {
    updateWalletStatus(
      walletId: walletId,
      status: WalletRestorationStatus.pending,
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

  /// Skip restoration (user requested)
  void skip() {
    AppLogger.wallet('Session restoration: Skipped by user');
    state = state.copyWith(
      phase: SessionRestorationPhase.completed,
      clearCurrentWallet: true,
    );
  }

  /// Mark restoration as timed out
  /// Handles partial success case where some sessions were restored
  void timeout({int? restoredCount}) {
    final elapsed = state.elapsed;
    AppLogger.wallet('Session restoration: Timed out', data: {
      'restoredSessions': restoredCount ?? state.restoredSessions,
      'totalSessions': state.totalSessions,
      'elapsedMs': elapsed?.inMilliseconds,
    });
    state = state.copyWith(
      phase: SessionRestorationPhase.timedOut,
      restoredSessions: restoredCount ?? state.restoredSessions,
      errorMessage: 'Restoration timed out after ${elapsed?.inSeconds ?? 30}s',
      clearCurrentWallet: true,
    );
  }

  /// Reset to initial state
  void reset() {
    state = const SessionRestorationState();
  }

  /// Update offline status
  void setOffline(bool offline) {
    if (state.isOffline != offline) {
      AppLogger.wallet('Session restoration: Offline status changed', data: {
        'isOffline': offline,
      });
      state = state.copyWith(isOffline: offline);
    }
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

/// Provider for checking if restoration timed out
final restorationTimedOutProvider = Provider<bool>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.isTimedOut;
});

/// Provider for checking if partial success (some sessions restored before timeout)
final restorationPartialSuccessProvider = Provider<bool>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.hasPartialSuccess;
});

/// Default restoration timeout duration
const Duration restorationTimeout = Duration(seconds: 30);

/// Provider for checking if device is offline during restoration
final restorationOfflineProvider = Provider<bool>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.isOffline;
});

/// Provider for individual wallet restoration info list
final walletRestorationListProvider = Provider<List<WalletRestorationInfo>>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.wallets;
});

/// Provider for failed wallets (for retry UI)
final failedWalletsProvider = Provider<List<WalletRestorationInfo>>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.wallets
      .where((w) => w.status == WalletRestorationStatus.failed)
      .toList();
});

/// Provider for whether any wallets failed
final hasWalletFailuresProvider = Provider<bool>((ref) {
  final state = ref.watch(sessionRestorationProvider);
  return state.hasFailures;
});
