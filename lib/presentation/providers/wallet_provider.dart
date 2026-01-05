import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/core/services/file_log_service.dart';
import 'package:wallet_integration_practice/data/datasources/local/wallet_local_datasource.dart';
import 'package:wallet_integration_practice/data/datasources/local/multi_session_datasource.dart';
import 'package:wallet_integration_practice/data/models/persisted_session_model.dart';
import 'package:wallet_integration_practice/data/models/coinbase_session_model.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';
import 'package:wallet_integration_practice/domain/entities/multi_wallet_state.dart';
import 'package:wallet_integration_practice/domain/entities/multi_session_state.dart';
import 'package:wallet_integration_practice/domain/entities/session_account.dart';
import 'package:wallet_integration_practice/wallet/wallet.dart';
import 'package:wallet_integration_practice/presentation/providers/balance_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/session_restoration_provider.dart';

/// Sentry 서비스 인스턴스 (편의를 위한 getter)
SentryService get _sentry => SentryService.instance;

// ============================================================================
// Phase 1.3: Persistence Retry Queue
// ============================================================================

/// Item in the persistence retry queue
class _PersistenceRetryItem {
  _PersistenceRetryItem({
    required this.wallet,
    required this.operation,
    DateTime? scheduledAt,
  })  : retryCount = 0,
        scheduledAt = scheduledAt ?? DateTime.now();

  final WalletEntity wallet;
  final Future<void> Function() operation;
  int retryCount;
  DateTime scheduledAt;

  /// Check if this item is ready for retry
  bool get isReady => DateTime.now().isAfter(scheduledAt);

  /// Schedule next retry with exponential backoff
  void scheduleNextRetry() {
    retryCount++;
    // Exponential backoff: 5s, 10s, 20s
    final delay = AppConstants.persistenceRetryInterval *
        (1 << (retryCount - 1).clamp(0, 2));
    scheduledAt = DateTime.now().add(delay);
  }
}

/// Queue for retrying failed persistence operations
///
/// When session persistence fails (e.g., due to network issues),
/// the operation is added to this queue and retried with exponential backoff.
class _PersistenceRetryQueue {
  _PersistenceRetryQueue();

  final List<_PersistenceRetryItem> _queue = [];
  Timer? _processTimer;
  bool _isProcessing = false;

  /// Whether the queue is currently active
  bool get isActive => _queue.isNotEmpty || _isProcessing;

  /// Number of items in the queue
  int get length => _queue.length;

  /// Enqueue a failed persistence operation for retry
  void enqueue(WalletEntity wallet, Future<void> Function() operation) {
    if (!AppConstants.enablePersistenceRetryQueue) {
      AppLogger.wallet('Persistence retry queue disabled, skipping enqueue');
      return;
    }

    // Check if already queued for this wallet
    final existing = _queue.indexWhere(
      (item) => item.wallet.address == wallet.address &&
          item.wallet.type == wallet.type,
    );

    if (existing >= 0) {
      // Update existing item's retry count and reschedule
      _queue[existing].scheduleNextRetry();
      AppLogger.wallet('Persistence retry rescheduled', data: {
        'address': wallet.address,
        'retryCount': _queue[existing].retryCount,
      });
    } else {
      // Add new item
      _queue.add(_PersistenceRetryItem(
        wallet: wallet,
        operation: operation,
      ));
      AppLogger.wallet('Persistence operation queued for retry', data: {
        'address': wallet.address,
        'queueLength': _queue.length,
      });
    }

    // Start processing if not already running
    _startProcessing();
  }

  /// Start the queue processor
  void _startProcessing() {
    if (_processTimer != null) return;

    // Check every second for ready items
    _processTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _processQueue();
    });
  }

  /// Process ready items in the queue
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;

    try {
      // Find ready items
      final readyItems = _queue.where((item) => item.isReady).toList();

      for (final item in readyItems) {
        // Check max retries
        if (item.retryCount >= AppConstants.maxPersistenceRetries) {
          AppLogger.wallet('Persistence retry exhausted', data: {
            'address': item.wallet.address,
            'maxRetries': AppConstants.maxPersistenceRetries,
          });
          _queue.remove(item);
          continue;
        }

        try {
          AppLogger.wallet('Retrying persistence operation', data: {
            'address': item.wallet.address,
            'attempt': item.retryCount + 1,
          });

          await item.operation();

          // Success - remove from queue
          _queue.remove(item);
          AppLogger.wallet('Persistence retry succeeded', data: {
            'address': item.wallet.address,
          });
        } catch (e) {
          // Failed - schedule next retry
          item.scheduleNextRetry();
          AppLogger.wallet('Persistence retry failed, rescheduling', data: {
            'address': item.wallet.address,
            'nextRetry': item.scheduledAt.toIso8601String(),
            'error': e.toString(),
          });
        }
      }

      // Stop timer if queue is empty
      if (_queue.isEmpty) {
        _stopProcessing();
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Stop the queue processor
  void _stopProcessing() {
    _processTimer?.cancel();
    _processTimer = null;
  }

  /// Dispose the queue
  void dispose() {
    _stopProcessing();
    _queue.clear();
  }
}

/// Provider for DeepLinkService
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService.instance;
});

/// Provider for deep link stream
final deepLinkStreamProvider = StreamProvider<Uri>((ref) {
  final service = ref.watch(deepLinkServiceProvider);
  return service.deepLinkStream;
});

/// Provider for PendingConnectionService
///
/// 앱이 백그라운드에서 종료된 후 Cold Start 시,
/// 대기 중인 연결 상태를 복원하기 위한 서비스
final pendingConnectionServiceProvider = Provider<PendingConnectionService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PendingConnectionService(prefs);
});

/// Provider for WalletLocalDataSource
///
/// 세션 지속성을 위한 로컬 데이터 소스 (레거시, 단일 세션)
final walletLocalDataSourceProvider = Provider<WalletLocalDataSource>((ref) {
  return WalletLocalDataSourceImpl();
});

/// Provider for MultiSessionDataSource
///
/// 다중 지갑 세션 지속성을 위한 데이터 소스
final multiSessionDataSourceProvider = Provider<MultiSessionDataSource>((ref) {
  return MultiSessionDataSourceImpl();
});

/// Provider for WalletService
final walletServiceProvider = Provider<WalletService>((ref) {
  final service = WalletService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for wallet connection status stream
final walletConnectionStreamProvider =
    StreamProvider<WalletConnectionStatus>((ref) {
  final service = ref.watch(walletServiceProvider);
  return service.connectionStream;
});

/// Provider for current connected wallet
final connectedWalletProvider = Provider<WalletEntity?>((ref) {
  final connectionStatus = ref.watch(walletConnectionStreamProvider);
  return connectionStatus.when(
    data: (status) => status.wallet,
    loading: () => null,
    error: (_, st) => null,
  );
});

/// Provider for wallet connection state
final walletConnectionStateProvider = Provider<WalletConnectionState>((ref) {
  final connectionStatus = ref.watch(walletConnectionStreamProvider);
  return connectionStatus.when(
    data: (status) => status.state,
    loading: () => WalletConnectionState.disconnected,
    error: (_, st) => WalletConnectionState.error,
  );
});

/// Provider for checking if wallet is connected
final isWalletConnectedProvider = Provider<bool>((ref) {
  final state = ref.watch(walletConnectionStateProvider);
  return state == WalletConnectionState.connected;
});

/// Provider for retry status during connection
final walletRetryStatusProvider = Provider<WalletRetryStatus>((ref) {
  final connectionStatus = ref.watch(walletConnectionStreamProvider);
  return connectionStatus.when(
    data: (status) => WalletRetryStatus(
      isRetrying: status.isRetrying,
      currentAttempt: status.retryCount ?? 0,
      maxAttempts: status.maxRetries ?? 0,
      message: status.progressMessage,
    ),
    loading: () => const WalletRetryStatus(),
    error: (_, st) => const WalletRetryStatus(),
  );
});

/// Retry status model for UI
class WalletRetryStatus {
  const WalletRetryStatus({
    this.isRetrying = false,
    this.currentAttempt = 0,
    this.maxAttempts = 0,
    this.message,
  });

  final bool isRetrying;
  final int currentAttempt;
  final int maxAttempts;
  final String? message;

  String get displayMessage {
    if (isRetrying) {
      return message ?? 'Retrying connection ($currentAttempt/$maxAttempts)...';
    }
    return message ?? 'Connecting...';
  }
}

/// Recovery options state for connection timeout/failure
class ConnectionRecoveryState {
  const ConnectionRecoveryState({
    this.showRecoveryOptions = false,
    this.connectionUri,
    this.walletType,
    this.shownAt,
    this.isCheckingOnResume = false,
    this.checkingMessage,
  });

  /// Factory for soft timeout checking state
  factory ConnectionRecoveryState.checkingAfterResume({
    required WalletType walletType,
    String? connectionUri,
  }) {
    return ConnectionRecoveryState(
      isCheckingOnResume: true,
      walletType: walletType,
      connectionUri: connectionUri,
      checkingMessage: '연결 확인 중...',
    );
  }

  /// Whether to show recovery options UI
  final bool showRecoveryOptions;

  /// The WalletConnect URI for QR/copy functionality
  final String? connectionUri;

  /// The wallet type currently being connected
  final WalletType? walletType;

  /// Time when recovery options were shown
  final DateTime? shownAt;

  /// Whether we're checking for session after resume from soft timeout
  final bool isCheckingOnResume;

  /// Message to display during checking
  final String? checkingMessage;

  /// Reset to initial state
  static const empty = ConnectionRecoveryState();

  ConnectionRecoveryState copyWith({
    bool? showRecoveryOptions,
    String? connectionUri,
    WalletType? walletType,
    DateTime? shownAt,
    bool? isCheckingOnResume,
    String? checkingMessage,
  }) {
    return ConnectionRecoveryState(
      showRecoveryOptions: showRecoveryOptions ?? this.showRecoveryOptions,
      connectionUri: connectionUri ?? this.connectionUri,
      walletType: walletType ?? this.walletType,
      shownAt: shownAt ?? this.shownAt,
      isCheckingOnResume: isCheckingOnResume ?? this.isCheckingOnResume,
      checkingMessage: checkingMessage ?? this.checkingMessage,
    );
  }
}

/// Notifier for wallet operations (Riverpod 3.0 - extends Notifier)
class WalletNotifier extends Notifier<AsyncValue<WalletEntity?>> {
  WalletService get _walletService => ref.read(walletServiceProvider);
  WalletLocalDataSource get _localDataSource => ref.read(walletLocalDataSourceProvider);
  MultiSessionDataSource get _multiSessionDataSource => ref.read(multiSessionDataSourceProvider);
  StreamSubscription<Uri>? _deepLinkSubscription;
  StreamSubscription<ConnectivityStatus>? _connectivitySubscription;

  /// Phase 1.3: Persistence retry queue for failed session saves
  final _persistenceRetryQueue = _PersistenceRetryQueue();

  /// Timer for approval timeout (shows recovery options after delay)
  Timer? _approvalTimeoutTimer;

  /// Duration before showing recovery options
  /// Extended to 45s to accommodate:
  /// - User review time in wallet app
  /// - Android background network restrictions
  /// - Relay reconnection attempts
  static const _approvalTimeoutDuration = Duration(seconds: 45);

  @override
  AsyncValue<WalletEntity?> build() {
    // Defer initialization to after build completes
    // This avoids Riverpod's "providers cannot modify other providers during initialization" error
    Future.microtask(() => _init());

    // Cleanup on dispose
    ref.onDispose(() {
      _deepLinkSubscription?.cancel();
      _connectivitySubscription?.cancel();
      _softTimeoutRecoverySubscription?.cancel();
      _softTimeoutRecoveryTimer?.cancel();
      ConnectivityService.instance.stopMonitoring();
      _cancelApprovalTimeout();
      _persistenceRetryQueue.dispose();
    });

    return const AsyncValue.data(null);
  }

  /// Start approval timeout timer
  void _startApprovalTimeout(WalletType walletType, String? uri) {
    _cancelApprovalTimeout();

    _approvalTimeoutTimer = Timer(_approvalTimeoutDuration, () {
      AppLogger.wallet('Approval timeout reached, showing recovery options', data: {
        'walletType': walletType.name,
        'hasUri': uri != null,
      });

      // Update recovery state to show options
      ref.read(connectionRecoveryProvider.notifier).showRecovery(
        walletType: walletType,
        connectionUri: uri,
      );
    });

    AppLogger.wallet('Started approval timeout timer', data: {
      'duration': _approvalTimeoutDuration.inSeconds,
      'walletType': walletType.name,
    });
  }

  /// Cancel approval timeout timer
  void _cancelApprovalTimeout() {
    _approvalTimeoutTimer?.cancel();
    _approvalTimeoutTimer = null;
  }

  /// Timer for soft timeout recovery window
  Timer? _softTimeoutRecoveryTimer;

  /// Subscription for soft timeout recovery
  StreamSubscription<WalletConnectionStatus>? _softTimeoutRecoverySubscription;

  /// Set up listener for session recovery after soft timeout
  void _setupSoftTimeoutRecoveryListener(
    WalletType walletType,
    int? chainId,
    String? cluster,
  ) {
    // Cancel any existing subscription
    _softTimeoutRecoverySubscription?.cancel();

    AppLogger.wallet('Setting up soft timeout recovery listener', data: {
      'walletType': walletType.name,
      'recoveryWindow': AppConstants.postSoftTimeoutRecoveryWindow.inSeconds,
    });

    // Listen for connection status changes
    _softTimeoutRecoverySubscription = _walletService.connectionStream.listen((status) {
      if (status.isConnected && status.wallet != null) {
        AppLogger.wallet('Soft timeout recovery: Session found!', data: {
          'address': status.wallet!.address,
        });

        // Cancel recovery timer
        _softTimeoutRecoveryTimer?.cancel();

        // Reset recovery state
        ref.read(connectionRecoveryProvider.notifier).reset();

        // Update state with connected wallet
        state = AsyncValue.data(status.wallet);

        // Save session for persistence
        unawaited(_saveSessionForPersistence(status.wallet!));

        // Track success
        _sentry.trackWalletConnectionSuccess(
          walletType: status.wallet!.type.name,
          address: status.wallet!.address,
          chainId: status.wallet!.chainId,
          cluster: status.wallet!.cluster,
        );

        WalletLogService.instance.endConnection(success: true);

        // Clean up subscription
        _softTimeoutRecoverySubscription?.cancel();
        _softTimeoutRecoverySubscription = null;
      }
    });

    // Set up timeout for recovery window
    _softTimeoutRecoveryTimer?.cancel();
    _softTimeoutRecoveryTimer = Timer(AppConstants.postSoftTimeoutRecoveryWindow, () {
      AppLogger.wallet('Soft timeout recovery window expired', data: {
        'walletType': walletType.name,
      });

      // Cancel subscription
      _softTimeoutRecoverySubscription?.cancel();
      _softTimeoutRecoverySubscription = null;

      // Check one last time if session was established
      if (_walletService.connectedWallet != null) {
        final wallet = _walletService.connectedWallet!;
        AppLogger.wallet('Soft timeout recovery: Late session found', data: {
          'address': wallet.address,
        });

        ref.read(connectionRecoveryProvider.notifier).reset();
        state = AsyncValue.data(wallet);
        unawaited(_saveSessionForPersistence(wallet));
        return;
      }

      // No session found - show error with recovery options
      ref.read(connectionRecoveryProvider.notifier).showRecovery(
        walletType: walletType,
      );

      state = AsyncValue.error(
        const WalletException(
          message: '연결 시간이 초과되었습니다. 다시 시도해 주세요.',
          code: 'TIMEOUT',
        ),
        StackTrace.current,
      );

      WalletLogService.instance.endConnection(success: false);
    });
  }

  // ============================================================================
  // Session Persistence Methods
  // ============================================================================

  /// Save session for persistence after successful connection
  ///
  /// Phase 1.3: On failure, enqueues to retry queue for automatic retry
  Future<void> _saveSessionForPersistence(WalletEntity wallet) async {
    try {
      await _performSessionPersistence(wallet);
    } catch (e, st) {
      // Phase 1.3: Enqueue for retry instead of just logging
      AppLogger.e('Failed to persist session, enqueueing for retry', e, st);

      _persistenceRetryQueue.enqueue(
        wallet,
        () => _performSessionPersistence(wallet),
      );
    }
  }

  /// Perform the actual session persistence operation
  ///
  /// Separated from _saveSessionForPersistence to enable retry queue
  Future<void> _performSessionPersistence(WalletEntity wallet) async {
    // Generate wallet ID
    final walletId = WalletIdGenerator.generate(wallet.type.name, wallet.address);

    // For WalletConnect-based wallets
    if (_isWalletConnectBased(wallet.type)) {
      // Get session topic from WalletService
      final sessionTopic = await _walletService.getSessionTopic();
      if (sessionTopic == null) {
        AppLogger.wallet('No session topic available, skipping persistence', data: {
          'walletType': wallet.type.name,
        });
        return;
      }

      // Get pairing topic for potential reconnection (crucial for multi-session)
      final pairingTopic = await _walletService.getPairingTopic();

      final now = DateTime.now();
      final session = PersistedSessionModel(
        walletType: wallet.type.name,
        sessionTopic: sessionTopic,
        address: wallet.address,
        chainId: wallet.chainId,
        cluster: wallet.cluster,
        createdAt: now,
        lastUsedAt: now,
        expiresAt: now.add(const Duration(days: 7)), // 7-day expiration
        pairingTopic: pairingTopic, // Store pairing topic for reconnection
      );

      // Save to multi-session storage
      await _multiSessionDataSource.saveWalletConnectSession(
        walletId: walletId,
        session: session,
      );

      // Set as active wallet
      await _multiSessionDataSource.setActiveWalletId(walletId);

      AppLogger.wallet('Session persisted to multi-session storage', data: {
        'walletId': walletId,
        'walletType': wallet.type.name,
        'address': wallet.address,
        'hasPairingTopic': pairingTopic != null,
      });
    } else if (wallet.type == WalletType.phantom) {
      // Phantom session is saved by the adapter, we just need to add to multi-session
      final phantomSession = await _localDataSource.getPhantomSession();
      if (phantomSession != null) {
        await _multiSessionDataSource.savePhantomSession(
          walletId: walletId,
          session: phantomSession,
        );
        await _multiSessionDataSource.setActiveWalletId(walletId);

        AppLogger.wallet('Phantom session persisted to multi-session storage', data: {
          'walletId': walletId,
          'address': wallet.address,
        });
      }
    } else if (_isNativeSdkBased(wallet.type)) {
      // Native SDK wallets (Coinbase) - store address-based session
      // No session topic needed - SDK is stateless/request-response based
      final now = DateTime.now();
      final session = CoinbaseSessionModel(
        address: wallet.address,
        chainId: wallet.chainId ?? 1,
        createdAt: now,
        lastUsedAt: now,
        expiresAt: now.add(const Duration(days: 30)), // 30-day expiration
      );

      await _multiSessionDataSource.saveCoinbaseSession(
        walletId: walletId,
        session: session,
      );
      await _multiSessionDataSource.setActiveWalletId(walletId);

      AppLogger.wallet('Coinbase session persisted to multi-session storage', data: {
        'walletId': walletId,
        'address': wallet.address,
        'chainId': wallet.chainId,
      });
    }
  }

  /// Check if wallet type uses WalletConnect protocol
  /// Note: Coinbase uses Native SDK, not WalletConnect
  bool _isWalletConnectBased(WalletType type) {
    return type == WalletType.walletConnect ||
        type == WalletType.metamask ||
        type == WalletType.trustWallet ||
        type == WalletType.okxWallet ||
        type == WalletType.rabby;
  }

  /// Check if wallet type uses Native SDK (not WalletConnect)
  /// These wallets require different persistence strategy
  bool _isNativeSdkBased(WalletType type) {
    return type == WalletType.coinbase;
  }

  Future<void> _init() async {
    AppLogger.wallet('WalletNotifier._init() called - starting wallet initialization');

    // Start session restoration tracking
    final restorationNotifier = ref.read(sessionRestorationProvider.notifier);
    final currentPhase = ref.read(sessionRestorationProvider).phase;
    
    // Only start restoration if in initial state (first app launch)
    // This prevents unnecessary skeleton UI when:
    // - Returning from WalletConnect modal without successful connection
    // - Restoration is already in progress
    // - Restoration has already completed
    if (currentPhase != SessionRestorationPhase.initial) {
      AppLogger.wallet('Session restoration not in initial state, skipping', data: {
        'currentPhase': currentPhase.name,
      });
      // Still initialize wallet service if needed
      await _walletService.initialize();
      return;
    }
    
    restorationNotifier.startChecking();

    // Check network connectivity before restoration
    final connectivityStatus = await ConnectivityService.instance.checkConnectivity();
    final isOffline = connectivityStatus == ConnectivityStatus.offline;
    restorationNotifier.setOffline(isOffline);

    if (isOffline) {
      AppLogger.wallet('Device is offline, skipping session restoration');
      // Start monitoring for connectivity restoration
      ConnectivityService.instance.startMonitoring();
      _setupConnectivityListener(restorationNotifier);

      // Load cached wallet info for offline display
      await _loadCachedWalletsForOfflineMode(restorationNotifier);
    }

    // Initialize wallet service (also registers deep link handlers)
    await _walletService.initialize();

    // Register session deletion callback for real-time SDK synchronization
    // This ensures local storage stays in sync when SDK deletes sessions
    _registerSessionDeletionHandler();

    // Migrate legacy single-session data to multi-session format
    // With timeout to prevent indefinite hanging
    // Skip restoration if offline (will retry when connectivity restored)
    final restorationSucceeded = isOffline
        ? false
        : await _performRestorationWithTimeout(restorationNotifier);

    // Check if WalletService already has a connected wallet
    // (e.g., from AppKit's internal session restoration)
    if (_walletService.connectedWallet != null) {
      state = AsyncValue.data(_walletService.connectedWallet);
      // Update persistence with current session (using multi-session storage)
      await _saveSessionForPersistence(_walletService.connectedWallet!);
    } else if (!restorationSucceeded) {
      // If restoration timed out and no wallet connected,
      // schedule a delayed retry for cases where network is slow to connect
      _scheduleDelayedRestoration();
    }

    // Mark restoration as complete only if not already marked (timeout/error)
    final finalPhase = ref.read(sessionRestorationProvider).phase;
    if (finalPhase == SessionRestorationPhase.restoring ||
        finalPhase == SessionRestorationPhase.checking) {
      restorationNotifier.complete();
    }

    // Subscribe to deep link stream for logging
    _deepLinkSubscription = DeepLinkService.instance.deepLinkStream.listen((uri) {
      AppLogger.d('WalletNotifier received deep link: $uri');
    });
  }

  /// Perform session restoration with timeout
  /// Returns true if restoration completed successfully, false if timed out
  Future<bool> _performRestorationWithTimeout(
    SessionRestorationNotifier restorationNotifier,
  ) async {
    try {
      // Use a Completer to race between restoration and timeout
      final completer = Completer<bool>();

      // Start the restoration task (runs in background, completes via completer)
      unawaited(_migrateAndRestoreAllSessions().then((_) {
        if (!completer.isCompleted) {
          completer.complete(true);
        }
      }).catchError((e, st) {
        AppLogger.e('Session restoration failed', e, st);
        if (!completer.isCompleted) {
          restorationNotifier.fail(e.toString());
          completer.complete(false);
        }
      }));

      // Set up timeout (runs in background, completes via completer)
      unawaited(Future.delayed(restorationTimeout).then((_) {
        if (!completer.isCompleted) {
          AppLogger.wallet('Session restoration timeout triggered', data: {
            'timeoutSeconds': restorationTimeout.inSeconds,
          });
          final currentState = ref.read(sessionRestorationProvider);
          restorationNotifier.timeout(restoredCount: currentState.restoredSessions);
          completer.complete(false);
        }
      }));

      // Wait for either completion or timeout
      return await completer.future;
    } catch (e, st) {
      AppLogger.e('Error during restoration with timeout', e, st);
      restorationNotifier.fail(e.toString());
      return false;
    }
  }

  /// Set up listener for connectivity changes
  /// When connectivity is restored, attempt session restoration
  void _setupConnectivityListener(SessionRestorationNotifier restorationNotifier) {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = ConnectivityService.instance.statusStream.listen((status) async {
      if (status == ConnectivityStatus.online) {
        AppLogger.wallet('Connectivity restored, attempting session restoration');
        restorationNotifier.setOffline(false);

        // Only attempt restoration if we haven't already restored
        if (state.value == null && _walletService.connectedWallet == null) {
          final success = await _performRestorationWithTimeout(restorationNotifier);
          if (success) {
            // Stop monitoring once restoration succeeds
            ConnectivityService.instance.stopMonitoring();
            unawaited(_connectivitySubscription?.cancel());
            _connectivitySubscription = null;
          }
        }
      } else if (status == ConnectivityStatus.offline) {
        restorationNotifier.setOffline(true);
      }
    });
  }

  /// Schedule a delayed restoration attempt
  /// This helps when initial restoration fails due to slow network/relay connection
  void _scheduleDelayedRestoration() {
    Future.delayed(const Duration(seconds: 3), () async {
      // Skip if already connected
      if (_walletService.connectedWallet != null) return;
      if (state.value != null) return;

      AppLogger.wallet('Attempting delayed session restoration...');

      try {
        final sessionState = await _multiSessionDataSource.getAllSessions();
        if (sessionState.isEmpty) return;

        // Try to restore active wallet session
        if (sessionState.activeWalletId != null) {
          final entry = sessionState.getSession(sessionState.activeWalletId!);
          if (entry != null) {
            // Pass the model directly (not entity) as _restoreSessionEntry expects model
            final wallet = await _restoreSessionEntry(entry);
            if (wallet != null) {
              state = AsyncValue.data(wallet);
              ref.read(multiWalletNotifierProvider.notifier).registerWallet(wallet);
              AppLogger.wallet('Delayed session restoration succeeded', data: {
                'address': wallet.address,
              });
            }
          }
        }
      } catch (e, st) {
        AppLogger.e('Delayed session restoration failed', e, st);
      }
    });
  }

  /// Migrate legacy sessions and restore all persisted sessions
  Future<void> _migrateAndRestoreAllSessions() async {
    final restorationNotifier = ref.read(sessionRestorationProvider.notifier);

    try {
      // 1. Migrate legacy single-session data to multi-session format
      final migrated = await _multiSessionDataSource.migrateLegacySessions();
      if (migrated) {
        AppLogger.wallet('Legacy sessions migrated to multi-session storage');
      }

      // 2. Remove any expired sessions
      final expiredCount = await _multiSessionDataSource.removeExpiredSessions();
      if (expiredCount > 0) {
        AppLogger.wallet('Removed expired sessions', data: {'count': expiredCount});
      }

      // 2.5 Clean up orphan sessions (topics in app storage but not in SDK)
      // This prevents wasteful restoration attempts on sessions that can't be restored
      await _cleanupOrphanSessions();

      // 3. Get all valid sessions
      final sessionState = await _multiSessionDataSource.getAllSessions();
      if (sessionState.isEmpty) {
        AppLogger.wallet('No persisted sessions found');
        restorationNotifier.completeNoSessions();
        return;
      }

      AppLogger.wallet('Restoring multi-wallet sessions', data: {
        'sessionCount': sessionState.count,
        'activeWalletId': sessionState.activeWalletId,
      });

      // Build wallet restoration info list for UI
      final walletInfoList = sessionState.sessionList.map((entry) {
        final walletTypeName = _getWalletTypeName(entry);
        final walletType = _getWalletTypeFromEntry(entry);
        return WalletRestorationInfo(
          walletId: entry.walletId,
          walletName: walletTypeName,
          walletType: walletType.name,
          status: WalletRestorationStatus.pending,
        );
      }).toList();

      // Begin restoration phase with total session count and wallet list
      restorationNotifier.beginRestoration(
        totalSessions: sessionState.count,
        wallets: walletInfoList,
      );

      // 4. Restore each session with progress updates
      WalletEntity? activeWallet;

      for (final entry in sessionState.sessionList) {
        // Mark this wallet as currently restoring
        restorationNotifier.startWalletRestoration(entry.walletId);

        try {
          final wallet = await _restoreSessionEntry(entry);
          if (wallet != null) {
            // Register with MultiWalletNotifier
            ref.read(multiWalletNotifierProvider.notifier).registerWallet(wallet);

            // Track the active wallet
            if (entry.walletId == sessionState.activeWalletId) {
              activeWallet = wallet;
            }

            // Mark wallet as successfully restored
            restorationNotifier.walletRestorationSuccess(entry.walletId);
          } else {
            // Wallet restoration returned null (failed silently)
            restorationNotifier.walletRestorationFailed(
              entry.walletId,
              '복원 실패',
            );
          }
        } catch (e) {
          // Mark wallet as failed with error message
          restorationNotifier.walletRestorationFailed(
            entry.walletId,
            e.toString(),
          );
        }
      }

      // 5. Fallback: Try restoring Phantom from legacy storage if not in multi-session
      final restoredWalletsState = ref.read(multiWalletNotifierProvider);
      final hasPhantom = restoredWalletsState.wallets.any(
        (entry) => entry.wallet.type == WalletType.phantom,
      );
      if (!hasPhantom) {
        final phantomSession = await _localDataSource.getPhantomSession();
        if (phantomSession != null && !phantomSession.toEntity().isExpired) {
          AppLogger.wallet('Attempting fallback Phantom restoration from legacy storage');

          final adapter = await _walletService.initializeAdapter(WalletType.phantom);
          if (adapter is PhantomAdapter) {
            adapter.setLocalDataSource(_localDataSource);
            final phantomWallet = await adapter.restoreSession();

            if (phantomWallet != null) {
              _walletService.setActiveAdapter(adapter, phantomWallet);

              // Save to MultiSessionDataSource for future
              await _multiSessionDataSource.savePhantomSession(
                walletId: 'phantom_${phantomWallet.address.substring(0, 8)}',
                session: phantomSession,
              );

              ref.read(multiWalletNotifierProvider.notifier).registerWallet(phantomWallet);
              activeWallet ??= phantomWallet;

              AppLogger.wallet('Phantom session restored from fallback', data: {
                'address': phantomWallet.address,
              });
            }
          }
        }
      }

      // 6. Set the active wallet state
      if (activeWallet != null) {
        state = AsyncValue.data(activeWallet);
        AppLogger.wallet('Active wallet restored', data: {
          'address': activeWallet.address,
          'type': activeWallet.type.name,
        });
      }
    } catch (e, st) {
      AppLogger.e('Failed to restore multi-wallet sessions', e, st);
      restorationNotifier.fail(e.toString());
    }
  }

  /// Get wallet type name from session entry for display
  String _getWalletTypeName(dynamic entry) {
    if (entry.sessionType == SessionType.walletConnect) {
      final wcSession = entry.walletConnectSession;
      if (wcSession != null) {
        final walletType = WalletType.values.firstWhere(
          (t) => t.name == wcSession.walletType,
          orElse: () => WalletType.walletConnect,
        );
        return walletType.displayName;
      }
    } else if (entry.sessionType == SessionType.phantom) {
      return WalletType.phantom.displayName;
    }
    return 'Wallet';
  }

  /// Get wallet type from session entry
  WalletType _getWalletTypeFromEntry(dynamic entry) {
    if (entry.sessionType == SessionType.walletConnect) {
      final wcSession = entry.walletConnectSession;
      if (wcSession != null) {
        return WalletType.values.firstWhere(
          (t) => t.name == wcSession.walletType,
          orElse: () => WalletType.walletConnect,
        );
      }
    } else if (entry.sessionType == SessionType.phantom) {
      return WalletType.phantom;
    }
    return WalletType.walletConnect;
  }

  /// Load cached wallet info for offline mode display
  /// Shows previously connected wallets even when offline
  Future<void> _loadCachedWalletsForOfflineMode(
    SessionRestorationNotifier restorationNotifier,
  ) async {
    try {
      // Get all persisted sessions without network calls
      final sessionState = await _multiSessionDataSource.getAllSessions();
      if (sessionState.isEmpty) {
        AppLogger.wallet('No cached sessions for offline display');
        restorationNotifier.completeNoSessions();
        return;
      }

      // Build wallet info list with "skipped" status (offline)
      final walletInfoList = sessionState.sessionList.map((entry) {
        final walletTypeName = _getWalletTypeName(entry);
        final walletType = _getWalletTypeFromEntry(entry);
        return WalletRestorationInfo(
          walletId: entry.walletId,
          walletName: walletTypeName,
          walletType: walletType.name,
          status: WalletRestorationStatus.skipped,
          errorMessage: '오프라인 - 연결 대기 중',
        );
      }).toList();

      AppLogger.wallet('Loaded cached wallets for offline display', data: {
        'walletCount': walletInfoList.length,
      });

      // Set up the UI with cached wallet info
      restorationNotifier.beginRestoration(
        totalSessions: sessionState.count,
        wallets: walletInfoList,
      );

      // Don't complete restoration - we're waiting for connectivity
      // The UI will show these wallets as "waiting for connection"
    } catch (e, st) {
      AppLogger.e('Failed to load cached wallets for offline mode', e, st);
      restorationNotifier.fail('캐시된 지갑 정보를 불러올 수 없습니다');
    }
  }

  /// Restore a single session entry
  Future<WalletEntity?> _restoreSessionEntry(
    dynamic entry, // MultiSessionEntryModel
  ) async {
    try {
      // Check session type and restore accordingly
      if (entry.sessionType == SessionType.walletConnect) {
        return await _restoreWalletConnectSession(entry);
      } else if (entry.sessionType == SessionType.phantom) {
        return await _restorePhantomSessionEntry(entry);
      } else if (entry.sessionType == SessionType.coinbase) {
        return await _restoreCoinbaseSessionEntry(entry);
      }
      return null;
    } catch (e, st) {
      AppLogger.e('Failed to restore session entry: ${entry.walletId}', e, st);
      // DO NOT remove failed session - preserve for potential future restoration
      // Unexpected errors shouldn't cause permanent data loss
      // Session will be marked as stale implicitly by returning null
      return null;
    }
  }

  /// Restore a WalletConnect-based session from entry
  /// Uses SessionRestoreResult to detect orphan sessions and handle them appropriately
  Future<WalletEntity?> _restoreWalletConnectSession(dynamic entry) async {
    final fileLog = FileLogService.instance;
    final wcSession = entry.walletConnectSession;
    final walletType = wcSession?.walletType;
    final isMetaMask = walletType?.toLowerCase().contains('metamask') ?? false;

    await fileLog.logRestore('_restoreWalletConnectSession START', {
      'walletId': entry.walletId,
      'walletType': walletType,
      'isMetaMask': isMetaMask,
    });

    AppLogger.wallet('_restoreWalletConnectSession called', data: {
      'walletId': entry.walletId,
      'sessionType': entry.sessionType.toString(),
    });

    if (wcSession == null) {
      await fileLog.logRestore('wcSession is NULL - cannot restore');
      return null;
    }

    final persistedSession = wcSession.toEntity();

    await fileLog.logRestore('Session data loaded', {
      'topic': persistedSession.sessionTopic.substring(0, 10),
      'address': persistedSession.address.substring(0, 10),
      'walletType': persistedSession.walletType,
      'isExpired': persistedSession.isExpired,
      'expiresAt': persistedSession.expiresAt?.toIso8601String(),
    });

    if (persistedSession.isExpired) {
      await fileLog.logRestore('SESSION EXPIRED - not restoring', {
        'walletId': entry.walletId,
        'expiresAt': persistedSession.expiresAt?.toIso8601String(),
      });
      AppLogger.wallet('WalletConnect session expired', data: {
        'walletId': entry.walletId,
      });
      return null;
    }

    final walletTypeEnum = WalletType.values.firstWhere(
      (t) => t.name == persistedSession.walletType,
      orElse: () => WalletType.walletConnect,
    );

    await fileLog.logRestore('Calling restoreSessionWithResult', {
      'walletType': walletTypeEnum.name,
      'topic': persistedSession.sessionTopic.substring(0, 10),
    });

    AppLogger.wallet('Attempting WalletConnect session restoration', data: {
      'walletType': persistedSession.walletType,
      'address': persistedSession.address,
    });

    // First attempt: use restoreSessionWithResult to get detailed status
    final result = await _walletService.restoreSessionWithResult(
      sessionTopic: persistedSession.sessionTopic,
      walletType: walletTypeEnum,
      fallbackAddress: persistedSession.address,
    );

    await fileLog.logRestore('restoreSessionWithResult returned', {
      'status': result.status.name,
      'isSuccess': result.isSuccess,
      'isOrphanSession': result.isOrphanSession,
      'shouldRetry': result.shouldRetry,
      'message': result.message,
    });

    // === CRITICAL: Handle orphan sessions - attempt pairing reconnection first ===
    // Orphan sessions are not in SDK but may be reconnectable via existing pairing.
    // We attempt auto-reconnection first, falling back to stale status if it fails.
    if (result.isOrphanSession) {
      await fileLog.logRestore('ORPHAN SESSION DETECTED - attempting pairing reconnection', {
        'walletId': entry.walletId,
        'walletType': walletTypeEnum.name,
        'hasPairingTopic': persistedSession.pairingTopic != null,
      });

      // Try pairing-based auto-reconnection if we have a pairing topic
      if (persistedSession.pairingTopic != null) {
        AppLogger.wallet('ORPHAN SESSION - attempting auto-reconnection via pairing', data: {
          'walletId': entry.walletId,
          'walletType': walletTypeEnum.name,
          'pairingTopic': '${persistedSession.pairingTopic!.substring(0, 8)}...',
        });

        try {
          final newSession = await _walletService.reconnectViaPairing(
            walletType: walletTypeEnum,
            pairingTopic: persistedSession.pairingTopic!,
            chainId: persistedSession.chainId,
          );

          if (newSession != null) {
            await fileLog.logRestore('PAIRING RECONNECTION SUCCESSFUL', {
              'walletId': entry.walletId,
              'newSessionTopic': newSession.topic.substring(0, 8),
            });

            // Extract address from new session
            final accounts = newSession.namespaces['eip155']?.accounts ?? [];
            final newAddress = accounts.isNotEmpty
                ? accounts.first.split(':').last
                : persistedSession.address;

            // Update stored session with new topic
            final updatedSession = PersistedSessionModel(
              sessionTopic: newSession.topic,
              address: newAddress,
              chainId: persistedSession.chainId,
              cluster: persistedSession.cluster,
              walletType: persistedSession.walletType,
              createdAt: persistedSession.createdAt,
              lastUsedAt: DateTime.now(),
              expiresAt: DateTime.fromMillisecondsSinceEpoch(newSession.expiry * 1000),
              pairingTopic: newSession.pairingTopic,
              peerName: newSession.peer.metadata.name,
              peerIconUrl: newSession.peer.metadata.icons.isNotEmpty
                  ? newSession.peer.metadata.icons.first
                  : null,
            );

            await _multiSessionDataSource.saveWalletConnectSession(
              walletId: entry.walletId,
              session: updatedSession,
            );

            AppLogger.wallet('ORPHAN SESSION RECOVERED via pairing reconnection', data: {
              'walletId': entry.walletId,
              'newAddress': newAddress,
            });

            return WalletEntity(
              address: newAddress,
              type: walletTypeEnum,
              chainId: persistedSession.chainId,
              cluster: persistedSession.cluster,
              sessionTopic: newSession.topic,
              connectedAt: DateTime.now(),
              isStale: false, // Successfully reconnected!
            );
          }
        } catch (e) {
          await fileLog.logRestore('PAIRING RECONNECTION FAILED', {
            'walletId': entry.walletId,
            'error': e.toString(),
          });
          AppLogger.wallet('Pairing reconnection failed - falling back to stale', data: {
            'walletId': entry.walletId,
            'error': e.toString(),
          });
        }
      }

      // Pairing reconnection failed or no pairing topic - mark as stale
      await fileLog.logRestore('ORPHAN SESSION - marked as STALE', {
        'walletId': entry.walletId,
        'walletType': walletTypeEnum.name,
      });
      AppLogger.wallet('ORPHAN SESSION - marking as stale (pairing reconnection unavailable)', data: {
        'walletId': entry.walletId,
        'walletType': walletTypeEnum.name,
        'message': result.message,
      });

      // DO NOT delete - preserve for potential manual reconnection
      // Return a stale WalletEntity so UI can show reconnect option
      return WalletEntity(
        address: persistedSession.address,
        type: walletTypeEnum,
        chainId: persistedSession.chainId,
        cluster: persistedSession.cluster,
        sessionTopic: persistedSession.sessionTopic,
        connectedAt: persistedSession.createdAt,
        isStale: true,
      );
    }

    // Handle successful restoration
    if (result.isSuccess && result.wallet != null) {
      // Update last used timestamp
      await _multiSessionDataSource.updateSessionLastUsed(entry.walletId);

      // If topic changed (found via fallback), update stored topic
      if (result.topicChanged && result.newTopic != null) {
        AppLogger.wallet('Session topic changed - updating stored topic', data: {
          'walletId': entry.walletId,
          'newTopic': '${result.newTopic!.substring(0, 10)}...',
        });
        // Create updated session model with new topic
        final updatedSession = PersistedSessionModel(
          sessionTopic: result.newTopic!,
          address: persistedSession.address,
          chainId: persistedSession.chainId,
          cluster: persistedSession.cluster,
          walletType: persistedSession.walletType,
          createdAt: persistedSession.createdAt,
          lastUsedAt: DateTime.now(),
          expiresAt: persistedSession.expiresAt,
        );
        await _multiSessionDataSource.saveWalletConnectSession(
          walletId: entry.walletId,
          session: updatedSession,
        );
      }

      AppLogger.wallet('WalletConnect session restored', data: {
        'address': result.wallet!.address,
      });
      return result.wallet;
    }

    // Only retry for relay disconnection (temporary network issues)
    if (result.shouldRetry) {
      AppLogger.wallet('Relay disconnection - retrying with backoff', data: {
        'status': result.status.name,
      });

      // Use exponential backoff with jitter for retry logic
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(milliseconds: 500),
        maxDelay: const Duration(seconds: 5),
        multiplier: 2.0,
        jitterFactor: 0.2,
        maxRetries: 2, // Reduced from 3 since we already tried once
      );

      while (backoff.hasMoreRetries) {
        final retryResult = await _walletService.restoreSessionWithResult(
          sessionTopic: persistedSession.sessionTopic,
          walletType: walletTypeEnum,
          fallbackAddress: persistedSession.address,
        );

        // Check for orphan on retry (SDK state may have changed)
        // Mark as stale instead of deleting - preserve for reconnection
        if (retryResult.isOrphanSession) {
          AppLogger.wallet('Session became orphan during retry - marking as stale', data: {
            'walletId': entry.walletId,
          });
          // Return stale entity instead of deleting
          return WalletEntity(
            address: persistedSession.address,
            type: walletTypeEnum,
            chainId: persistedSession.chainId,
            cluster: persistedSession.cluster,
            sessionTopic: persistedSession.sessionTopic,
            connectedAt: persistedSession.createdAt,
            isStale: true,
          );
        }

        if (retryResult.isSuccess && retryResult.wallet != null) {
          await _multiSessionDataSource.updateSessionLastUsed(entry.walletId);
          AppLogger.wallet('WalletConnect session restored on retry', data: {
            'address': retryResult.wallet!.address,
            'attempt': backoff.currentRetry + 1,
          });
          return retryResult.wallet;
        }

        // Don't retry for non-relay issues
        if (!retryResult.shouldRetry) {
          break;
        }

        final delay = backoff.currentDelay;
        AppLogger.wallet('Session restoration retry', data: {
          'attempt': backoff.currentRetry + 1,
          'nextDelayMs': delay.inMilliseconds,
        });
        backoff.incrementRetry();
        await Future.delayed(delay);
      }
    }

    AppLogger.wallet('WalletConnect session restoration failed', data: {
      'walletType': persistedSession.walletType,
      'address': persistedSession.address,
      'finalStatus': result.status.name,
    });

    return null;
  }

  /// Pre-restoration cleanup: Remove orphan sessions before attempting restoration
  ///
  /// Orphan sessions occur when the app's local storage has session topics
  /// that no longer exist in the WalletConnect SDK. This happens when:
  /// - A new wallet connection replaces existing sessions in the SDK
  /// - Sessions expire on the SDK side but app storage isn't updated
  /// - SDK state is cleared but app storage persists
  ///
  /// By cleaning up orphans before restoration, we avoid:
  /// - Wasteful retry attempts on sessions that can never be restored
  /// - User-facing delays from failed restoration attempts
  ///
  /// NOTE: Multi-session support change (2024-01):
  /// - Sessions NOT in SDK are no longer deleted (SDK only keeps 1 active session)
  /// - Only EXPIRED sessions are removed
  /// - This allows multiple wallet sessions to persist across app restarts
  Future<void> _cleanupOrphanSessions() async {
    try {
      final sessionState = await _multiSessionDataSource.getAllSessions();
      final wcSessions = sessionState.sessionList
          .where((e) => e.sessionType == SessionType.walletConnect)
          .toList();

      if (wcSessions.isEmpty) {
        AppLogger.wallet('No WalletConnect sessions to check');
        return;
      }

      AppLogger.wallet('Checking WalletConnect sessions for expiration', data: {
        'wcSessionCount': wcSessions.length,
      });

      // Only remove expired sessions - keep sessions even if not in SDK
      // (SDK only maintains single active session, but we want multi-session support)
      int expiredCount = 0;
      int staleCount = 0;

      // Get SDK topics for informational logging only
      final sdkTopics = await _walletService.getActiveSdkTopics();

      for (final entry in wcSessions) {
        final session = entry.walletConnectSession;
        if (session == null) continue;

        final storedTopic = session.toEntity().sessionTopic;
        final isInSdk = sdkTopics.contains(storedTopic);

        // Step 1: Check expiration - remove expired sessions
        if (session.isExpired) {
          AppLogger.wallet('Expired session detected - removing', data: {
            'walletId': entry.walletId,
            'topicPreview': storedTopic.length > 8
                ? '${storedTopic.substring(0, 8)}...'
                : storedTopic,
            'expiresAt': session.expiresAt?.toIso8601String(),
          });
          await _multiSessionDataSource.removeSession(entry.walletId);
          expiredCount++;
          continue;
        }

        // Step 2: Log sessions not in SDK but keep them (stale but valid)
        if (!isInSdk) {
          AppLogger.wallet('Session not in SDK but not expired - keeping as stale', data: {
            'walletId': entry.walletId,
            'walletType': session.walletType,
            'topicPreview': storedTopic.length > 8
                ? '${storedTopic.substring(0, 8)}...'
                : storedTopic,
          });
          staleCount++;
        }
      }

      AppLogger.wallet('Session cleanup complete', data: {
        'expiredRemoved': expiredCount,
        'staleKept': staleCount,
        'totalRemaining': wcSessions.length - expiredCount,
      });
    } catch (e, st) {
      // Don't fail restoration if cleanup fails - just log and continue
      AppLogger.e('Session cleanup failed', e, st);
    }
  }

  /// Register session deletion callback for real-time sync
  ///
  /// This ensures that when SDK deletes sessions (e.g., when connecting a new wallet),
  /// the app's local storage is updated immediately.
  void _registerSessionDeletionHandler() {
    _walletService.registerSessionDeletedCallback((String topic) async {
      AppLogger.wallet('Session deleted by SDK - syncing local storage', data: {
        'deletedTopic': '${topic.substring(0, 8)}...',
      });

      try {
        // Find and remove the session with this topic
        final sessionState = await _multiSessionDataSource.getAllSessions();
        for (final entry in sessionState.sessionList) {
          if (entry.sessionType == SessionType.walletConnect) {
            final storedTopic = entry.walletConnectSession?.toEntity().sessionTopic;
            if (storedTopic == topic) {
              AppLogger.wallet('Removing deleted session from local storage', data: {
                'walletId': entry.walletId,
              });
              await _multiSessionDataSource.removeSession(entry.walletId);
              break;
            }
          }
        }
      } catch (e, st) {
        AppLogger.e('Failed to sync deleted session', e, st);
      }
    });
  }

  /// Restore a Phantom session from entry
  /// Includes retry logic with exponential backoff and jitter
  Future<WalletEntity?> _restorePhantomSessionEntry(dynamic entry) async {
    final phantomSession = entry.phantomSession;
    if (phantomSession == null) return null;

    final session = phantomSession.toEntity();
    if (session.isExpired) {
      AppLogger.wallet('Phantom session expired', data: {
        'walletId': entry.walletId,
      });
      return null;
    }

    AppLogger.wallet('Attempting Phantom session restoration', data: {
      'address': session.connectedAddress,
      'cluster': session.cluster,
    });

    // Use exponential backoff with jitter for retry logic
    final backoff = ExponentialBackoff(
      initialDelay: const Duration(milliseconds: 500),
      maxDelay: const Duration(seconds: 5),
      multiplier: 2.0,
      jitterFactor: 0.2,
      maxRetries: 3,
    );

    while (backoff.hasMoreRetries) {
      try {
        // Initialize PhantomAdapter with localDataSource
        final adapter = await _walletService.initializeAdapter(WalletType.phantom);
        if (adapter is PhantomAdapter) {
          adapter.setLocalDataSource(_localDataSource);

          // Save phantom session to legacy storage for adapter restoration
          await _localDataSource.savePhantomSession(phantomSession);

          // Attempt to restore the session
          final wallet = await adapter.restoreSession();

          if (wallet != null) {
            // Set the adapter as active
            _walletService.setActiveAdapter(adapter, wallet);

            // Update last used timestamp
            await _multiSessionDataSource.updateSessionLastUsed(entry.walletId);

            AppLogger.wallet('Phantom session restored', data: {
              'address': wallet.address,
              'attempt': backoff.currentRetry + 1,
            });
            return wallet;
          }
        }
      } catch (e) {
        AppLogger.w('Phantom restoration attempt ${backoff.currentRetry + 1} failed: $e');
      }

      // If more retries available, wait with exponential backoff
      if (backoff.hasMoreRetries) {
        final delay = backoff.currentDelay;
        AppLogger.wallet('Phantom session restoration attempt failed, retrying...', data: {
          'attempt': backoff.currentRetry + 1,
          'maxRetries': backoff.maxRetries,
          'nextDelayMs': delay.inMilliseconds,
        });
        backoff.incrementRetry();
        await Future.delayed(delay);
      } else {
        break;
      }
    }

    AppLogger.wallet('Phantom session restoration failed after retries', data: {
      'address': session.connectedAddress,
      'cluster': session.cluster,
      'attempts': backoff.maxRetries,
    });

    return null;
  }

  /// Restore a Coinbase session from entry
  /// Coinbase SDK is stateless (request-response), so no actual reconnection needed
  /// We just restore the adapter state from persisted address/chainId
  Future<WalletEntity?> _restoreCoinbaseSessionEntry(dynamic entry) async {
    final coinbaseSession = entry.coinbaseSession;
    if (coinbaseSession == null) return null;

    final session = coinbaseSession.toEntity();
    if (session.isExpired) {
      AppLogger.wallet('Coinbase session expired', data: {
        'walletId': entry.walletId,
      });
      return null;
    }

    AppLogger.wallet('Attempting Coinbase session restoration', data: {
      'address': session.address,
      'chainId': session.chainId,
    });

    try {
      // Coinbase SDK is stateless - we just need to restore adapter state
      // No actual reconnection required unlike WalletConnect
      final adapter = await _walletService.initializeAdapter(WalletType.coinbase);
      if (adapter is CoinbaseWalletAdapter) {
        // Restore adapter state with persisted address/chainId
        adapter.restoreState(
          address: session.address,
          chainId: session.chainId,
        );

        // Create wallet entity from restored state
        final wallet = WalletEntity(
          address: session.address,
          type: WalletType.coinbase,
          chainId: session.chainId,
          connectedAt: session.createdAt,
        );

        // Set the adapter as active
        _walletService.setActiveAdapter(adapter, wallet);

        // Update last used timestamp
        await _multiSessionDataSource.updateSessionLastUsed(entry.walletId);

        AppLogger.wallet('Coinbase session restored', data: {
          'address': wallet.address,
          'chainId': wallet.chainId,
        });
        return wallet;
      }
    } catch (e) {
      AppLogger.w('Coinbase restoration failed: $e');
    }

    AppLogger.wallet('Coinbase session restoration failed', data: {
      'address': session.address,
      'chainId': session.chainId,
    });

    return null;
  }

  /// Connect to a wallet
  /// Uses stream as source of truth for final connection state
  Future<void> connect({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) async {
    state = const AsyncValue.loading();

    // Reset recovery state at start of new connection
    ref.read(connectionRecoveryProvider.notifier).reset();

    // [Sentry] Track connection start
    _sentry.trackWalletConnectionStart(
      walletType: walletType.name,
      chainId: chainId,
      cluster: cluster,
    );

    // [WalletLogService] Start structured connection logging
    WalletLogService.instance.startConnection(
      walletType: walletType,
      chainId: chainId,
      cluster: cluster,
    );

    // Use Completer to wait for final result from stream
    final completer = Completer<WalletEntity>();
    StreamSubscription<WalletConnectionStatus>? statusSubscription;

    statusSubscription = _walletService.connectionStream.listen((status) {
      AppLogger.wallet('Connection status update', data: {
        'state': status.state.name,
        'isRetrying': status.isRetrying,
        'retryCount': status.retryCount,
        'hasError': status.hasError,
      });

      // [Sentry] Add breadcrumb for status changes
      _sentry.addBreadcrumb(
        message: 'Connection status: ${status.state.name}',
        category: 'wallet.connection',
        data: {
          'is_retrying': status.isRetrying,
          'retry_count': status.retryCount,
          'has_error': status.hasError,
        },
        level: status.hasError ? SentryLevel.warning : SentryLevel.info,
      );

      if (status.isConnected && status.wallet != null) {
        // Final success - complete with wallet
        // Cancel timeout and reset recovery state
        _cancelApprovalTimeout();
        ref.read(connectionRecoveryProvider.notifier).reset();

        if (!completer.isCompleted) {
          AppLogger.wallet('Stream: Connection successful, completing');
          completer.complete(status.wallet);
        }
      } else if (status.hasError && !status.isRetrying) {
        // Final error (not during retry) - complete with error
        // Cancel timeout but keep recovery options visible for retry
        _cancelApprovalTimeout();

        if (!completer.isCompleted) {
          AppLogger.wallet('Stream: Final error, completing with error');
          completer.completeError(
            WalletException(
              message: status.errorMessage ?? 'Connection failed',
              code: 'CONNECTION_ERROR',
            ),
          );
        }
      }
      // If isRetrying, we wait for the next status update
    });

    try {
      // Set localDataSource on PhantomAdapter before connection
      // This ensures session can be saved when deep link callback returns
      if (walletType == WalletType.phantom) {
        final adapter = await _walletService.initializeAdapter(WalletType.phantom);
        if (adapter is PhantomAdapter) {
          adapter.setLocalDataSource(_localDataSource);
        }
      }

      // Start connection - don't await the result directly
      // The stream will tell us the final outcome
      unawaited(
        _walletService.connect(
          walletType: walletType,
          chainId: chainId,
          cluster: cluster,
        ).then((_) {
          // Success handled by stream
        }).catchError((e, st) {
          // Log but don't propagate - stream is source of truth
          AppLogger.wallet('Connect method threw (stream is source of truth)', data: {
            'error': e.toString(),
          });
          // Forward error to completer if not already completed
          // This fixes the race condition where exception propagates before stream emits error
          if (!completer.isCompleted) {
            completer.completeError(e, st);
          }
        }),
      );

      // Get URI for recovery options (QR code / copy)
      // Small delay to ensure URI is generated after connect() starts
      Future.delayed(const Duration(milliseconds: 500), () async {
        final uri = await _walletService.getConnectionUri();
        if (uri != null && !completer.isCompleted) {
          // Start approval timeout with URI for recovery
          _startApprovalTimeout(walletType, uri);
        }
      });

      // Wait for result from stream
      final wallet = await completer.future;

      // [Sentry] Track connection success
      _sentry.trackWalletConnectionSuccess(
        walletType: wallet.type.name,
        address: wallet.address,
        chainId: wallet.chainId,
        cluster: wallet.cluster,
      );

      // [WalletLogService] End connection successfully
      WalletLogService.instance.endConnection(success: true);

      // Save session for persistence (blocking to ensure data is saved before app exit)
      await _saveSessionForPersistence(wallet);

      state = AsyncValue.data(wallet);
    } catch (e, st) {
      // Check for SOFT_TIMEOUT (background timeout that may recover on resume)
      final walletException = e is WalletException ? e : null;
      if (walletException?.code == 'SOFT_TIMEOUT') {
        AppLogger.wallet('Soft timeout detected - keeping recovery window open', data: {
          'walletType': walletType.name,
          'message': walletException?.message,
        });

        // Show "checking" UI instead of error
        ref.read(connectionRecoveryProvider.notifier).showCheckingOnResume(
          walletType: walletType,
        );

        // Keep loading state - adapter will handle recovery on resume
        state = const AsyncValue.loading();

        // [Sentry] Track as breadcrumb (not error - this is recoverable)
        _sentry.addBreadcrumb(
          message: 'Soft timeout - waiting for recovery',
          category: 'wallet.connection',
          data: {
            'wallet_type': walletType.name,
            'chain_id': chainId,
          },
          level: SentryLevel.info,
        );

        // Set up listener for session recovery
        _setupSoftTimeoutRecoveryListener(walletType, chainId, cluster);
        return; // Don't propagate as error
      }

      // [Sentry] Track connection failure
      await _sentry.trackWalletConnectionFailure(
        walletType: walletType.name,
        error: e,
        stackTrace: st,
        errorStep: 'Stream completion',
        chainId: chainId,
        cluster: cluster,
      );

      // [WalletLogService] End connection with failure
      WalletLogService.instance.endConnection(success: false);

      state = AsyncValue.error(e, st);
    } finally {
      await statusSubscription.cancel();
    }
  }

  /// Disconnect from wallet
  Future<void> disconnect() async {
    final currentWallet = state.value;

    // [Sentry] Track disconnection
    _sentry.trackWalletDisconnection(
      walletType: currentWallet?.type.name ?? 'unknown',
      address: currentWallet?.address,
      reason: 'user_initiated',
    );

    try {
      await _walletService.disconnect();

      // Clear persisted session from multi-session storage
      if (currentWallet != null) {
        final walletId = WalletIdGenerator.generate(
          currentWallet.type.name,
          currentWallet.address,
        );
        unawaited(_multiSessionDataSource.removeSession(walletId).catchError((e) {
          AppLogger.e('Failed to remove session from multi-session storage', e);
        }));
      }

      // Clear legacy persisted session (non-blocking, best-effort)
      unawaited(_localDataSource.clearPersistedSession().catchError((e) {
        AppLogger.e('Failed to clear persisted session', e);
      }));

      state = const AsyncValue.data(null);
    } catch (e, st) {
      // [Sentry] Capture disconnect error
      await _sentry.captureException(
        e,
        stackTrace: st,
        tags: {'error_type': 'wallet_disconnect'},
      );

      // Still try to clear persisted sessions even on error
      if (currentWallet != null) {
        final walletId = WalletIdGenerator.generate(
          currentWallet.type.name,
          currentWallet.address,
        );
        unawaited(_multiSessionDataSource.removeSession(walletId).catchError((e) {
          AppLogger.w('Failed to remove session during error cleanup (walletId: $walletId): $e');
        }));
      }
      unawaited(_localDataSource.clearPersistedSession().catchError((e) {
        AppLogger.w('Failed to clear persisted session during error cleanup: $e');
      }));

      state = AsyncValue.error(e, st);
    }
  }

  /// Switch chain
  Future<void> switchChain(int chainId) async {
    final currentChainId = state.value?.chainId ?? 0;

    try {
      await _walletService.switchChain(chainId);

      // [Sentry] Track chain switch success
      _sentry.trackChainSwitch(
        fromChainId: currentChainId,
        toChainId: chainId,
        success: true,
      );

      // Update state with new chain ID if needed
      if (state.value != null) {
        state = AsyncValue.data(state.value!.copyWith(chainId: chainId));
      }
    } catch (e, st) {
      // [Sentry] Track chain switch failure
      _sentry.trackChainSwitch(
        fromChainId: currentChainId,
        toChainId: chainId,
        success: false,
        error: e.toString(),
      );

      await _sentry.captureException(
        e,
        stackTrace: st,
        tags: {
          'error_type': 'chain_switch',
          'from_chain': currentChainId.toString(),
          'to_chain': chainId.toString(),
        },
      );

      state = AsyncValue.error(e, st);
    }
  }

  /// Get connection URI
  Future<String?> getConnectionUri() async {
    return _walletService.getConnectionUri();
  }
}

/// Provider for wallet notifier (Riverpod 3.0 - uses NotifierProvider)
final walletNotifierProvider =
    NotifierProvider<WalletNotifier, AsyncValue<WalletEntity?>>(
  WalletNotifier.new,
);

/// Provider for supported wallets
/// Deep link: MetaMask, OKX Wallet, Trust Wallet, Phantom, Rabby
/// Other flows: Coinbase Wallet (SDK), WalletConnect (QR)
final supportedWalletsProvider = Provider<List<WalletInfo>>((ref) {
  return [
    WalletInfo(
      type: WalletType.metamask,
      name: 'MetaMask',
      description: 'Popular browser-based wallet',
      iconUrl: WalletType.metamask.iconAsset,
      supportsEvm: true,
      supportsSolana: false,
    ),
    WalletInfo(
      type: WalletType.coinbase,
      name: 'Coinbase Wallet',
      description: 'Mobile & Chrome extension wallet',
      iconUrl: WalletType.coinbase.iconAsset,
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.okxWallet,
      name: 'OKX Wallet',
      description: 'Multi-chain wallet by OKX',
      iconUrl: WalletType.okxWallet.iconAsset,
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.trustWallet,
      name: 'Trust Wallet',
      description: 'Multi-chain mobile wallet',
      iconUrl: WalletType.trustWallet.iconAsset,
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.phantom,
      name: 'Phantom',
      description: 'Solana & Ethereum wallet',
      iconUrl: WalletType.phantom.iconAsset,
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.rabby,
      name: 'Rabby',
      description: 'Multi-chain browser wallet',
      iconUrl: WalletType.rabby.iconAsset,
      supportsEvm: true,
      supportsSolana: false,
    ),
    WalletInfo(
      type: WalletType.walletConnect,
      name: 'WalletConnect',
      description: 'Connect any supported wallet',
      iconUrl: WalletType.walletConnect.iconAsset,
      supportsEvm: true,
      supportsSolana: true,
    ),
  ];
});

/// Wallet info model for display
class WalletInfo {
  const WalletInfo({
    required this.type,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.supportsEvm,
    required this.supportsSolana,
  });

  final WalletType type;
  final String name;
  final String description;
  final String iconUrl;
  final bool supportsEvm;
  final bool supportsSolana;
}

// ============================================================================
// Multi-Wallet State Management
// ============================================================================

/// Notifier for managing multiple wallet connections (Riverpod 3.0)
class MultiWalletNotifier extends Notifier<MultiWalletState> {
  WalletService get _walletService => ref.read(walletServiceProvider);
  WalletLocalDataSource get _localDataSource => ref.read(walletLocalDataSourceProvider);
  MultiSessionDataSource get _multiSessionDataSource => ref.read(multiSessionDataSourceProvider);

  @override
  MultiWalletState build() {
    // CRITICAL: Trigger WalletNotifier initialization to restore sessions on cold start
    // Without this, walletNotifierProvider is never read and _init() is never called
    // This fixes the issue where MetaMask connection is lost after app kill/restart
    ref.read(walletNotifierProvider);

    return const MultiWalletState();
  }

  /// Connect a new wallet and add to the list
  Future<void> connectWallet({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) async {
    // Create a temporary entry for the connecting wallet
    final tempWallet = WalletEntity(
      address: 'connecting...',
      type: walletType,
      chainId: chainId,
      cluster: cluster,
      connectedAt: DateTime.now(),
    );
    final tempId = '${walletType.name}_connecting_${DateTime.now().millisecondsSinceEpoch}';

    // Add connecting entry to state
    final connectingEntry = ConnectedWalletEntry(
      id: tempId,
      wallet: tempWallet,
      status: WalletEntryStatus.connecting,
      lastActivityAt: DateTime.now(),
    );
    state = state.addWallet(connectingEntry);

    // Use Completer to wait for result from stream
    final completer = Completer<WalletEntity>();
    StreamSubscription<WalletConnectionStatus>? statusSubscription;

    statusSubscription = _walletService.connectionStream.listen((status) {
      if (status.isConnected && status.wallet != null) {
        if (!completer.isCompleted) {
          completer.complete(status.wallet);
        }
      } else if (status.hasError && !status.isRetrying) {
        if (!completer.isCompleted) {
          completer.completeError(
            WalletException(
              message: status.errorMessage ?? 'Connection failed',
              code: 'CONNECTION_ERROR',
            ),
          );
        }
      }
    });

    // [Sentry] Track connection start
    _sentry.trackWalletConnectionStart(
      walletType: walletType.name,
      chainId: chainId,
      cluster: cluster,
    );

    // [WalletLogService] Start structured connection logging (MultiWallet)
    WalletLogService.instance.startConnection(
      walletType: walletType,
      chainId: chainId,
      cluster: cluster,
    );

    try {
      // Set localDataSource on PhantomAdapter before connection
      // This ensures session can be saved when deep link callback returns
      if (walletType == WalletType.phantom) {
        final adapter = await _walletService.initializeAdapter(WalletType.phantom);
        if (adapter is PhantomAdapter) {
          adapter.setLocalDataSource(_localDataSource);
        }
      }

      // Start connection - don't await, stream is source of truth
      unawaited(_walletService
          .connect(
            walletType: walletType,
            chainId: chainId,
            cluster: cluster,
          )
          .then((_) {
            // Success handled by stream
          }).catchError((e, st) {
            AppLogger.wallet('Connect threw (stream is source of truth)', data: {
              'error': e.toString(),
            });
            // Forward error to completer if not already completed
            // This fixes the race condition where exception propagates before stream emits error
            if (!completer.isCompleted) {
              completer.completeError(e, st);
            }
          }));

      // Wait for result
      final wallet = await completer.future;

      // Remove temp entry and add real entry
      final realId = ConnectedWalletEntry.generateId(wallet);

      // Check if wallet already exists
      if (state.containsWallet(realId)) {
        // Update existing entry
        state = state.removeWallet(tempId);
        state = state.updateWallet(realId, (entry) {
          return entry.copyWith(
            wallet: wallet,
            status: WalletEntryStatus.connected,
            errorMessage: null,
            lastActivityAt: DateTime.now(),
          );
        });
      } else {
        // Replace temp with real entry
        state = state.removeWallet(tempId);
        final newEntry = ConnectedWalletEntry.connected(
          wallet,
          isActive: !state.hasActiveWallet, // First wallet becomes active
        );
        state = state.addWallet(newEntry);

        // Set as active if first wallet
        if (!state.hasActiveWallet || state.connectedCount == 1) {
          state = state.setActiveWallet(realId);
        }
      }

      // [Sentry] Track connection success
      _sentry.trackWalletConnectionSuccess(
        walletType: wallet.type.name,
        address: wallet.address,
        chainId: wallet.chainId,
        cluster: wallet.cluster,
      );

      // [WalletLogService] End connection successfully (MultiWallet)
      WalletLogService.instance.endConnection(success: true);

      // Save session to multi-session storage (non-blocking)
      unawaited(_saveWalletSession(wallet));

      AppLogger.wallet('Multi-wallet: Added wallet', data: {
        'id': realId,
        'type': wallet.type.name,
        'address': wallet.address,
        'totalWallets': state.totalCount,
      });
    } catch (e, st) {
      // Check if this is an expected failure (user behavior, not a bug)
      // Expected failures: TIMEOUT, USER_REJECTED, USER_CANCELLED, CANCELLED
      final walletException = e is WalletException ? e : null;
      final isExpectedFailure = walletException != null &&
          WalletConstants.expectedFailureCodes.contains(walletException.code);

      if (isExpectedFailure) {
        // Expected failures - log locally but don't send to Sentry as error
        // These are normal user behaviors (didn't approve in time, rejected, etc.)
        AppLogger.wallet('Expected connection failure', data: {
          'walletType': walletType.name,
          'errorCode': walletException.code,
          'message': walletException.message,
        });

        // Track as breadcrumb only (not as error event)
        // This provides context for debugging without cluttering error reports
        _sentry.addBreadcrumb(
          message: 'Wallet connection expected failure: ${walletException.code}',
          category: 'wallet.connection',
          data: {
            'wallet_type': walletType.name,
            'error_code': walletException.code,
            'chain_id': chainId,
          },
          level: SentryLevel.info,
        );
      } else {
        // Unexpected failures - report to Sentry as error
        // These are actual bugs or system issues that need investigation
        await _sentry.trackWalletConnectionFailure(
          walletType: walletType.name,
          error: e,
          stackTrace: st,
          errorStep: 'MultiWallet connection',
          chainId: chainId,
          cluster: cluster,
        );
      }

      // [WalletLogService] End connection with failure (MultiWallet)
      WalletLogService.instance.endConnection(success: false);

      // Update temp entry with error (for both expected and unexpected)
      state = state.updateWallet(tempId, (entry) {
        return entry.copyWith(
          status: WalletEntryStatus.error,
          errorMessage: e.toString(),
        );
      });
      AppLogger.e('Multi-wallet: Connection failed', e);
    } finally {
      await statusSubscription.cancel();
    }
  }

  /// Register an already connected wallet (e.g. from session restoration)
  void registerWallet(WalletEntity wallet) {
    // 1. Remove any pending/connecting entries for this wallet type
    // This prevents duplicate "Connecting..." placeholders from remaining
    final connectingEntries = state.wallets.where(
      (w) => w.wallet.type == wallet.type && w.status == WalletEntryStatus.connecting
    ).toList();
    
    for (final entry in connectingEntries) {
      state = state.removeWallet(entry.id);
    }

    final realId = ConnectedWalletEntry.generateId(wallet);

    // Check if wallet already exists
    if (state.containsWallet(realId)) {
      // Ensure it's active if it's the only one or currently connected
      if (!state.hasActiveWallet) {
        state = state.setActiveWallet(realId);
      }
      return;
    }

    final newEntry = ConnectedWalletEntry.connected(
      wallet,
      isActive: !state.hasActiveWallet,
    );
    state = state.addWallet(newEntry);

    // Set as active if first wallet
    if (!state.hasActiveWallet || state.connectedCount == 1) {
      state = state.setActiveWallet(realId);
    }
    
    AppLogger.wallet('Multi-wallet: Registered restored wallet', data: {
      'id': realId,
      'address': wallet.address,
    });
  }

  /// Disconnect a specific wallet by ID
  Future<void> disconnectWallet(String walletId) async {
    final entry = state.getWallet(walletId);
    if (entry == null) return;

    // Update status to indicate disconnecting
    state = state.updateWallet(walletId, (e) {
      return e.copyWith(status: WalletEntryStatus.connecting);
    });

    try {
      // If this is the active wallet, we need to handle WalletService
      if (entry.isActive) {
        await _walletService.disconnect();
      }

      // Remove from multi-session storage
      final sessionWalletId = WalletIdGenerator.generate(
        entry.wallet.type.name,
        entry.wallet.address,
      );
      unawaited(_multiSessionDataSource.removeSession(sessionWalletId).catchError((e) {
        AppLogger.e('Failed to remove session from multi-session storage', e);
      }));

      // Remove from list
      state = state.removeWallet(walletId);

      AppLogger.wallet('Multi-wallet: Disconnected wallet', data: {
        'id': walletId,
        'remainingWallets': state.totalCount,
      });
    } catch (e) {
      // Still remove on error - also remove from multi-session storage
      final sessionWalletId = WalletIdGenerator.generate(
        entry.wallet.type.name,
        entry.wallet.address,
      );
      unawaited(_multiSessionDataSource.removeSession(sessionWalletId).catchError((removeError) {
        AppLogger.w('Failed to remove session during error cleanup (sessionWalletId: $sessionWalletId): $removeError');
      }));
      state = state.removeWallet(walletId);
      AppLogger.e('Multi-wallet: Error during disconnect', e);
    }
  }

  /// Cancel any pending/connecting wallet entries
  /// 
  /// Called when user dismisses connection modal without completing connection.
  /// This cleans up temporary "connecting" entries from the state.
  void cancelPendingConnections({WalletType? walletType}) {
    // Find all connecting entries (optionally filtered by wallet type)
    final connectingEntries = state.wallets.where((entry) {
      final isConnecting = entry.status == WalletEntryStatus.connecting;
      if (walletType != null) {
        return isConnecting && entry.wallet.type == walletType;
      }
      return isConnecting;
    }).toList();

    // Remove each connecting entry
    for (final entry in connectingEntries) {
      state = state.removeWallet(entry.id);
      AppLogger.wallet('Multi-wallet: Cancelled pending connection', data: {
        'id': entry.id,
        'walletType': entry.wallet.type.name,
      });
    }
  }

  /// Set a wallet as the active wallet for operations
  Future<void> setActiveWallet(String walletId) async {
    final entry = state.getWallet(walletId);
    if (entry == null || entry.status != WalletEntryStatus.connected) return;

    // Update state
    state = state.setActiveWallet(walletId);

    // If we need to switch the WalletService to use this wallet's adapter,
    // we would do that here. For now, we just track in UI.
    AppLogger.wallet('Multi-wallet: Set active wallet', data: {
      'id': walletId,
      'address': entry.wallet.address,
    });
  }

  /// Remove a wallet from the list (for errored/disconnected wallets)
  void removeWallet(String walletId) {
    state = state.removeWallet(walletId);
    AppLogger.wallet('Multi-wallet: Removed wallet', data: {
      'id': walletId,
      'remainingWallets': state.totalCount,
    });
  }

  /// Retry connection for an errored wallet
  Future<void> reconnectWallet(String walletId) async {
    final entry = state.getWallet(walletId);
    if (entry == null) return;

    // Remove the old entry
    state = state.removeWallet(walletId);

    // Try to connect again
    await connectWallet(
      walletType: entry.wallet.type,
      chainId: entry.wallet.chainId,
      cluster: entry.wallet.cluster,
    );
  }

  /// Clear all wallets
  Future<void> clearAll() async {
    // Clear multi-session storage
    unawaited(_multiSessionDataSource.clearAllSessions().catchError((e) {
      AppLogger.e('Failed to clear all sessions from storage', e);
    }));
    state = const MultiWalletState();
  }

  /// Save wallet session to multi-session storage
  Future<void> _saveWalletSession(WalletEntity wallet) async {
    try {
      final walletId = WalletIdGenerator.generate(wallet.type.name, wallet.address);

      // Check if this is a WalletConnect-based wallet
      if (_isWalletConnectBased(wallet.type)) {
        // Get session topic from WalletService
        final sessionTopic = await _walletService.getSessionTopic();
        if (sessionTopic == null) {
          AppLogger.wallet('No session topic available for MultiWallet persistence', data: {
            'walletType': wallet.type.name,
          });
          return;
        }

        final now = DateTime.now();
        final session = PersistedSessionModel(
          walletType: wallet.type.name,
          sessionTopic: sessionTopic,
          address: wallet.address,
          chainId: wallet.chainId,
          cluster: wallet.cluster,
          createdAt: now,
          lastUsedAt: now,
          expiresAt: now.add(const Duration(days: 7)),
        );

        await _multiSessionDataSource.saveWalletConnectSession(
          walletId: walletId,
          session: session,
        );
        await _multiSessionDataSource.setActiveWalletId(walletId);

        AppLogger.wallet('MultiWallet: Session saved', data: {
          'walletId': walletId,
          'walletType': wallet.type.name,
        });
      } else if (wallet.type == WalletType.phantom) {
        // Phantom session is saved by the adapter
        final phantomSession = await _localDataSource.getPhantomSession();
        if (phantomSession != null) {
          await _multiSessionDataSource.savePhantomSession(
            walletId: walletId,
            session: phantomSession,
          );
          await _multiSessionDataSource.setActiveWalletId(walletId);

          AppLogger.wallet('MultiWallet: Phantom session saved', data: {
            'walletId': walletId,
          });
        }
      } else if (_isNativeSdkBased(wallet.type)) {
        // Coinbase uses Native SDK - save address and chainId for state restoration
        final now = DateTime.now();
        final session = CoinbaseSessionModel(
          address: wallet.address,
          chainId: wallet.chainId ?? 1,
          createdAt: now,
          lastUsedAt: now,
          expiresAt: now.add(const Duration(days: 30)), // 30-day validity
        );

        await _multiSessionDataSource.saveCoinbaseSession(
          walletId: walletId,
          session: session,
        );
        await _multiSessionDataSource.setActiveWalletId(walletId);

        AppLogger.wallet('MultiWallet: Coinbase session saved', data: {
          'walletId': walletId,
          'address': wallet.address,
          'chainId': wallet.chainId,
        });
      }
    } catch (e, st) {
      AppLogger.e('Failed to save wallet session in MultiWallet', e, st);
    }
  }

  /// Check if wallet type uses WalletConnect protocol
  /// Note: Coinbase uses Native SDK, not WalletConnect
  bool _isWalletConnectBased(WalletType type) {
    return type == WalletType.walletConnect ||
        type == WalletType.metamask ||
        type == WalletType.trustWallet ||
        type == WalletType.okxWallet ||
        type == WalletType.rabby;
  }

  /// Check if wallet type uses Native SDK (not WalletConnect)
  /// These wallets require different persistence strategy
  bool _isNativeSdkBased(WalletType type) {
    return type == WalletType.coinbase;
  }
}

/// Provider for multi-wallet notifier (Riverpod 3.0 - uses NotifierProvider)
final multiWalletNotifierProvider =
    NotifierProvider<MultiWalletNotifier, MultiWalletState>(
  MultiWalletNotifier.new,
);

/// Provider for list of connected wallets
final connectedWalletsProvider = Provider<List<ConnectedWalletEntry>>((ref) {
  return ref.watch(multiWalletNotifierProvider).connectedWallets;
});

/// Provider for all wallet entries (including disconnected/errored)
final allWalletEntriesProvider = Provider<List<ConnectedWalletEntry>>((ref) {
  return ref.watch(multiWalletNotifierProvider).wallets;
});

/// Provider for active wallet entry
final activeWalletEntryProvider = Provider<ConnectedWalletEntry?>((ref) {
  return ref.watch(multiWalletNotifierProvider).activeWallet;
});

/// Provider for connected wallet count
final walletCountProvider = Provider<int>((ref) {
  return ref.watch(multiWalletNotifierProvider).connectedCount;
});

/// Provider for checking if any wallet is connecting
final hasConnectingWalletProvider = Provider<bool>((ref) {
  return ref.watch(multiWalletNotifierProvider).hasConnectingWallet;
});

/// Provider for checking if any wallet has error
final hasErrorWalletProvider = Provider<bool>((ref) {
  return ref.watch(multiWalletNotifierProvider).hasErrorWallet;
});

// ============================================================================
// Session Accounts Management (Multi-Account from Single Wallet)
// ============================================================================

/// Provider for session accounts stream
final sessionAccountsStreamProvider = StreamProvider<SessionAccounts>((ref) {
  final service = ref.watch(walletServiceProvider);
  return service.accountsChangedStream;
});

/// Provider for current session accounts
final sessionAccountsProvider = Provider<SessionAccounts>((ref) {
  // Watch the stream for updates
  final streamData = ref.watch(sessionAccountsStreamProvider);

  // Return stream data if available, otherwise get from service
  return streamData.when(
    data: (accounts) => accounts,
    loading: () => ref.read(walletServiceProvider).sessionAccounts,
    error: (_, _) => ref.read(walletServiceProvider).sessionAccounts,
  );
});

/// Provider for checking if session has multiple accounts
final hasMultipleAccountsProvider = Provider<bool>((ref) {
  final accounts = ref.watch(sessionAccountsProvider);
  return accounts.hasMultipleAddresses;
});

/// Provider for active account address
final activeAccountAddressProvider = Provider<String?>((ref) {
  final accounts = ref.watch(sessionAccountsProvider);
  return accounts.activeAddress;
});

/// Provider for active session account
final activeSessionAccountProvider = Provider<SessionAccount?>((ref) {
  final accounts = ref.watch(sessionAccountsProvider);
  return accounts.activeAccount;
});

/// Provider for unique addresses in session
final sessionAddressesProvider = Provider<List<String>>((ref) {
  final accounts = ref.watch(sessionAccountsProvider);
  return accounts.uniqueAddresses;
});

/// Provider for all session accounts list
final sessionAccountsListProvider = Provider<List<SessionAccount>>((ref) {
  final accounts = ref.watch(sessionAccountsProvider);
  return accounts.accounts;
});

/// Notifier for managing active account selection
class ActiveAccountNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Initialize with current active address from service
    final accounts = ref.watch(sessionAccountsProvider);
    return accounts.activeAddress;
  }

  /// Set the active account for transactions
  bool setActiveAccount(String address) {
    final service = ref.read(walletServiceProvider);
    final success = service.setActiveAccount(address);
    if (success) {
      state = address;
      AppLogger.wallet('Active account set via notifier', data: {
        'address': address,
      });
    }
    return success;
  }

  /// Reset to default (first account)
  void resetToDefault() {
    final accounts = ref.read(sessionAccountsProvider);
    if (accounts.isNotEmpty) {
      setActiveAccount(accounts.accounts.first.address);
    }
  }
}

/// Provider for active account notifier
final activeAccountNotifierProvider = NotifierProvider<ActiveAccountNotifier, String?>(
  ActiveAccountNotifier.new,
);

/// Provider for checking if account selector should be shown
/// Returns true if connected and has multiple accounts
final shouldShowAccountSelectorProvider = Provider<bool>((ref) {
  final isConnected = ref.watch(isWalletConnectedProvider);
  final hasMultiple = ref.watch(hasMultipleAccountsProvider);
  return isConnected && hasMultiple;
});

/// Provider for getting the address to use for transactions.
///
/// Returns the active session account address if available,
/// otherwise falls back to the connected wallet address.
/// This should be used when creating transaction or signing requests.
final transactionAddressProvider = Provider<String?>((ref) {
  // First, try to get active session account address
  final activeAccountAddress = ref.watch(activeAccountAddressProvider);
  if (activeAccountAddress != null) {
    return activeAccountAddress;
  }

  // Fallback to connected wallet address
  final connectedWallet = ref.watch(connectedWalletProvider);
  return connectedWallet?.address;
});

/// Provider for getting the address to use for transactions (non-null).
///
/// Throws if no address is available.
final requiredTransactionAddressProvider = Provider<String>((ref) {
  final address = ref.watch(transactionAddressProvider);
  if (address == null) {
    throw const WalletException(
      message: 'No wallet address available for transaction',
      code: 'NO_ADDRESS',
    );
  }
  return address;
});

// ============================================================================
// Connection Recovery State Management
// ============================================================================

/// Notifier for managing connection recovery options
class ConnectionRecoveryNotifier extends Notifier<ConnectionRecoveryState> {
  @override
  ConnectionRecoveryState build() {
    return ConnectionRecoveryState.empty;
  }

  /// Show recovery options with connection details
  void showRecovery({
    required WalletType walletType,
    String? connectionUri,
  }) {
    state = ConnectionRecoveryState(
      showRecoveryOptions: true,
      connectionUri: connectionUri,
      walletType: walletType,
      shownAt: DateTime.now(),
    );

    AppLogger.wallet('Recovery options shown', data: {
      'walletType': walletType.name,
      'hasUri': connectionUri != null,
    });
  }

  /// Hide recovery options and reset state
  void reset() {
    if (state.showRecoveryOptions || state.isCheckingOnResume) {
      AppLogger.wallet('Recovery options reset');
    }
    state = ConnectionRecoveryState.empty;
  }

  /// Show "checking on resume" state for soft timeout recovery
  void showCheckingOnResume({
    required WalletType walletType,
    String? connectionUri,
  }) {
    state = ConnectionRecoveryState.checkingAfterResume(
      walletType: walletType,
      connectionUri: connectionUri,
    );

    AppLogger.wallet('Soft timeout - showing checking state', data: {
      'walletType': walletType.name,
    });
  }

  /// Update checking message
  void updateCheckingMessage(String message) {
    state = state.copyWith(checkingMessage: message);
  }

  /// Update connection URI (e.g., when it becomes available)
  void updateUri(String uri) {
    state = state.copyWith(connectionUri: uri);
  }
}

/// Provider for connection recovery state
final connectionRecoveryProvider =
    NotifierProvider<ConnectionRecoveryNotifier, ConnectionRecoveryState>(
  ConnectionRecoveryNotifier.new,
);

/// Provider for checking if recovery options should be shown
final showRecoveryOptionsProvider = Provider<bool>((ref) {
  return ref.watch(connectionRecoveryProvider).showRecoveryOptions;
});

/// Provider for recovery connection URI
final recoveryConnectionUriProvider = Provider<String?>((ref) {
  return ref.watch(connectionRecoveryProvider).connectionUri;
});

/// Provider for recovery wallet type
final recoveryWalletTypeProvider = Provider<WalletType?>((ref) {
  return ref.watch(connectionRecoveryProvider).walletType;
});
