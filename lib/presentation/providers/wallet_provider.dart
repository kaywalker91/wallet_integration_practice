import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';
import 'package:wallet_integration_practice/domain/entities/multi_wallet_state.dart';
import 'package:wallet_integration_practice/domain/entities/session_account.dart';
import 'package:wallet_integration_practice/wallet/wallet.dart';
import 'package:wallet_integration_practice/presentation/providers/balance_provider.dart';

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
  final bool isRetrying;
  final int currentAttempt;
  final int maxAttempts;
  final String? message;

  const WalletRetryStatus({
    this.isRetrying = false,
    this.currentAttempt = 0,
    this.maxAttempts = 0,
    this.message,
  });

  String get displayMessage {
    if (isRetrying) {
      return message ?? 'Retrying connection ($currentAttempt/$maxAttempts)...';
    }
    return message ?? 'Connecting...';
  }
}

/// Recovery options state for connection timeout/failure
class ConnectionRecoveryState {
  /// Whether to show recovery options UI
  final bool showRecoveryOptions;

  /// The WalletConnect URI for QR/copy functionality
  final String? connectionUri;

  /// The wallet type currently being connected
  final WalletType? walletType;

  /// Time when recovery options were shown
  final DateTime? shownAt;

  const ConnectionRecoveryState({
    this.showRecoveryOptions = false,
    this.connectionUri,
    this.walletType,
    this.shownAt,
  });

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
  StreamSubscription<Uri>? _deepLinkSubscription;

  /// Timer for approval timeout (shows recovery options after 15 seconds)
  Timer? _approvalTimeoutTimer;

  /// Duration before showing recovery options
  static const _approvalTimeoutDuration = Duration(seconds: 15);

  @override
  AsyncValue<WalletEntity?> build() {
    // Initialize on build
    _init();

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

  Future<void> _init() async {
    // Initialize wallet service (also registers deep link handlers)
    await _walletService.initialize();
    if (_walletService.connectedWallet != null) {
      state = AsyncValue.data(_walletService.connectedWallet);
    }

    // Subscribe to deep link stream for logging
    _deepLinkSubscription = DeepLinkService.instance.deepLinkStream.listen((uri) {
      AppLogger.d('WalletNotifier received deep link: $uri');
    });
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
      state = const AsyncValue.data(null);
    } catch (e, st) {
      // [Sentry] Capture disconnect error
      await _sentry.captureException(
        e,
        stackTrace: st,
        tags: {'error_type': 'wallet_disconnect'},
      );
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

/// Provider for supported wallets (deep link only - QR removed)
/// Supported: MetaMask, Trust Wallet, Phantom, Rabby
/// Removed: WalletConnect (QR only), Coinbase (no deep link), Rainbow (no deep link)
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
  final WalletType type;
  final String name;
  final String description;
  final String iconUrl;
  final bool supportsEvm;
  final bool supportsSolana;

  const WalletInfo({
    required this.type,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.supportsEvm,
    required this.supportsSolana,
  });
}

// ============================================================================
// Multi-Wallet State Management
// ============================================================================

/// Notifier for managing multiple wallet connections (Riverpod 3.0)
class MultiWalletNotifier extends Notifier<MultiWalletState> {
  WalletService get _walletService => ref.read(walletServiceProvider);

  @override
  MultiWalletState build() {
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
      // Start connection - don't await, stream is source of truth
      _walletService.connect(
        walletType: walletType,
        chainId: chainId,
        cluster: cluster,
      ).then((_) {
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
      });

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

      AppLogger.wallet('Multi-wallet: Added wallet', data: {
        'id': realId,
        'type': wallet.type.name,
        'address': wallet.address,
        'totalWallets': state.totalCount,
      });
    } catch (e, st) {
      // Check if this is an expected failure (user behavior, not a bug)
      // Expected failures: TIMEOUT, USER_REJECTED, USER_CANCELLED, CANCELLED
      final isExpectedFailure = e is WalletException &&
          WalletConstants.expectedFailureCodes.contains(e.code);

      if (isExpectedFailure) {
        // Expected failures - log locally but don't send to Sentry as error
        // These are normal user behaviors (didn't approve in time, rejected, etc.)
        AppLogger.wallet('Expected connection failure', data: {
          'walletType': walletType.name,
          'errorCode': (e as WalletException).code,
          'message': e.message,
        });

        // Track as breadcrumb only (not as error event)
        // This provides context for debugging without cluttering error reports
        _sentry.addBreadcrumb(
          message: 'Wallet connection expected failure: ${(e as WalletException).code}',
          category: 'wallet.connection',
          data: {
            'wallet_type': walletType.name,
            'error_code': e.code,
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

      // Remove from list
      state = state.removeWallet(walletId);

      AppLogger.wallet('Multi-wallet: Disconnected wallet', data: {
        'id': walletId,
        'remainingWallets': state.totalCount,
      });
    } catch (e) {
      // Still remove on error
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
  void clearAll() {
    state = const MultiWalletState();
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
    error: (_, __) => ref.read(walletServiceProvider).sessionAccounts,
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
