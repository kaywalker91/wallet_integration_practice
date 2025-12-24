import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/data/datasources/local/wallet_local_datasource.dart';
import 'package:wallet_integration_practice/data/datasources/local/multi_session_datasource.dart';
import 'package:wallet_integration_practice/data/models/persisted_session_model.dart';
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
  });

  /// Whether to show recovery options UI
  final bool showRecoveryOptions;

  /// The WalletConnect URI for QR/copy functionality
  final String? connectionUri;

  /// The wallet type currently being connected
  final WalletType? walletType;

  /// Time when recovery options were shown
  final DateTime? shownAt;

  ConnectionRecoveryState copyWith({
    bool? showRecoveryOptions,
    String? connectionUri,
    WalletType? walletType,
    DateTime? shownAt,
  }) {
    return ConnectionRecoveryState(
      showRecoveryOptions: showRecoveryOptions ?? this.showRecoveryOptions,
      connectionUri: connectionUri ?? this.connectionUri,
      walletType: walletType ?? this.walletType,
      shownAt: shownAt ?? this.shownAt,
    );
  }

  /// Reset to initial state
  static const empty = ConnectionRecoveryState();
}

/// Notifier for wallet operations (Riverpod 3.0 - extends Notifier)
class WalletNotifier extends Notifier<AsyncValue<WalletEntity?>> {
  WalletService get _walletService => ref.read(walletServiceProvider);
  WalletLocalDataSource get _localDataSource => ref.read(walletLocalDataSourceProvider);
  MultiSessionDataSource get _multiSessionDataSource => ref.read(multiSessionDataSourceProvider);
  StreamSubscription<Uri>? _deepLinkSubscription;

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
      _cancelApprovalTimeout();
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

  // ============================================================================
  // Session Persistence Methods
  // ============================================================================

  /// Save session for persistence after successful connection
  Future<void> _saveSessionForPersistence(WalletEntity wallet) async {
    try {
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
      }
    } catch (e, st) {
      // Non-critical operation, log but don't throw
      AppLogger.e('Failed to persist session', e, st);
    }
  }

  /// Check if wallet type uses WalletConnect protocol
  bool _isWalletConnectBased(WalletType type) {
    return type == WalletType.walletConnect ||
        type == WalletType.metamask ||
        type == WalletType.trustWallet ||
        type == WalletType.okxWallet ||
        type == WalletType.coinbase ||
        type == WalletType.rabby;
  }

  Future<void> _init() async {
    AppLogger.wallet('WalletNotifier._init() called - starting wallet initialization');

    // Start session restoration tracking
    final restorationNotifier = ref.read(sessionRestorationProvider.notifier);
    restorationNotifier.startChecking();

    // Initialize wallet service (also registers deep link handlers)
    await _walletService.initialize();

    // Migrate legacy single-session data to multi-session format
    await _migrateAndRestoreAllSessions();

    // Check if WalletService already has a connected wallet
    // (e.g., from AppKit's internal session restoration)
    if (_walletService.connectedWallet != null) {
      state = AsyncValue.data(_walletService.connectedWallet);
      // Update persistence with current session (using multi-session storage)
      await _saveSessionForPersistence(_walletService.connectedWallet!);
    } else {
      // If no wallet connected after initial restoration attempt,
      // schedule a delayed retry for cases where network is slow to connect
      _scheduleDelayedRestoration();
    }

    // Mark restoration as complete
    restorationNotifier.complete();

    // Subscribe to deep link stream for logging
    _deepLinkSubscription = DeepLinkService.instance.deepLinkStream.listen((uri) {
      AppLogger.d('WalletNotifier received deep link: $uri');
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

      // Begin restoration phase with total session count
      restorationNotifier.beginRestoration(totalSessions: sessionState.count);

      // 4. Restore each session with progress updates
      WalletEntity? activeWallet;
      var restoredCount = 0;

      for (final entry in sessionState.sessionList) {
        // Update progress with current wallet name
        final walletTypeName = _getWalletTypeName(entry);
        restorationNotifier.updateProgress(
          restoredCount: restoredCount,
          currentWalletName: walletTypeName,
        );

        final wallet = await _restoreSessionEntry(entry);
        if (wallet != null) {
          // Register with MultiWalletNotifier
          ref.read(multiWalletNotifierProvider.notifier).registerWallet(wallet);

          // Track the active wallet
          if (entry.walletId == sessionState.activeWalletId) {
            activeWallet = wallet;
          }
        }

        restoredCount++;
      }

      // Final progress update
      restorationNotifier.updateProgress(
        restoredCount: restoredCount,
        currentWalletName: null,
      );

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
      }
      return null;
    } catch (e, st) {
      AppLogger.e('Failed to restore session entry: ${entry.walletId}', e, st);
      // Remove failed session
      await _multiSessionDataSource.removeSession(entry.walletId);
      return null;
    }
  }

  /// Restore a WalletConnect-based session from entry
  /// Includes retry logic with relay connection waiting
  Future<WalletEntity?> _restoreWalletConnectSession(dynamic entry) async {
    final wcSession = entry.walletConnectSession;
    if (wcSession == null) return null;

    final persistedSession = wcSession.toEntity();
    if (persistedSession.isExpired) {
      AppLogger.wallet('WalletConnect session expired', data: {
        'walletId': entry.walletId,
      });
      return null;
    }

    final walletType = WalletType.values.firstWhere(
      (t) => t.name == persistedSession.walletType,
      orElse: () => WalletType.walletConnect,
    );

    AppLogger.wallet('Attempting WalletConnect session restoration', data: {
      'walletType': persistedSession.walletType,
      'address': persistedSession.address,
    });

    // Attempt restoration with retries
    // Relay connection might not be ready immediately after cold start
    const maxRetries = 3;
    const retryDelays = [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ];

    for (var attempt = 0; attempt < maxRetries; attempt++) {
      // Attempt restoration via WalletService
      final wallet = await _walletService.restoreSession(
        sessionTopic: persistedSession.sessionTopic,
        walletType: walletType,
      );

      if (wallet != null) {
        // Update last used timestamp
        await _multiSessionDataSource.updateSessionLastUsed(entry.walletId);
        AppLogger.wallet('WalletConnect session restored', data: {
          'address': wallet.address,
          'attempt': attempt + 1,
        });
        return wallet;
      }

      // If not last attempt, wait before retry
      if (attempt < maxRetries - 1) {
        AppLogger.wallet('Session restoration attempt failed, retrying...', data: {
          'attempt': attempt + 1,
          'maxRetries': maxRetries,
          'nextDelay': retryDelays[attempt].inMilliseconds,
        });
        await Future.delayed(retryDelays[attempt]);
      }
    }

    AppLogger.wallet('WalletConnect session restoration failed after retries', data: {
      'walletType': persistedSession.walletType,
      'address': persistedSession.address,
      'attempts': maxRetries,
    });

    return null;
  }

  /// Restore a Phantom session from entry
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
        });
        return wallet;
      }
    }

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
        unawaited(_multiSessionDataSource.removeSession(walletId).catchError((_) {}));
      }
      unawaited(_localDataSource.clearPersistedSession().catchError((_) {}));

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
      unawaited(_multiSessionDataSource.removeSession(sessionWalletId).catchError((_) {}));
      state = state.removeWallet(walletId);
      AppLogger.e('Multi-wallet: Error during disconnect', e);
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
      }
    } catch (e, st) {
      AppLogger.e('Failed to save wallet session in MultiWallet', e, st);
    }
  }

  /// Check if wallet type uses WalletConnect protocol
  bool _isWalletConnectBased(WalletType type) {
    return type == WalletType.walletConnect ||
        type == WalletType.metamask ||
        type == WalletType.trustWallet ||
        type == WalletType.okxWallet ||
        type == WalletType.coinbase ||
        type == WalletType.rabby;
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
    if (state.showRecoveryOptions) {
      AppLogger.wallet('Recovery options reset');
    }
    state = ConnectionRecoveryState.empty;
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
