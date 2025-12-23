import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/entities/session_account.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';

/// WalletConnect v2 adapter implementation using Reown AppKit
///
/// Supports multiple accounts from a single wallet session.
/// The wallet (e.g., MetaMask) decides which accounts to share,
/// and this adapter manages which account is "active" for transactions.
///
/// Implements [WidgetsBindingObserver] to detect app lifecycle changes
/// and proactively check for session updates when app resumes from background.
class WalletConnectAdapter extends EvmWalletAdapter with WidgetsBindingObserver {
  WalletConnectAdapter({WalletAdapterConfig? config})
      : _config = config ?? WalletAdapterConfig.defaultConfig();

  final WalletAdapterConfig _config;

  ReownAppKit? _appKit;
  SessionData? _session;
  String? _uri;

  /// The chainId that was requested during connect().
  /// This is used instead of parsing from session accounts,
  /// because the wallet may return accounts for multiple chains
  /// and the first one may not be the requested chain.
  int? _requestedChainId;

  /// Get the chainId that was requested during the last connect() call.
  /// Returns null if no connection has been requested yet.
  int? get requestedChainId => _requestedChainId;

  /// Manages multiple accounts from the session
  SessionAccounts _sessionAccounts = const SessionAccounts.empty();

  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();

  /// Stream controller for account changes
  final _accountsChangedController = StreamController<SessionAccounts>.broadcast();

  /// Track relay connection state for cold start recovery
  bool _isRelayConnected = false;

  /// Whether a relay reconnection is currently in progress
  /// Used to prevent multiple simultaneous reconnection attempts
  bool _isReconnecting = false;

  /// Source of the current reconnection attempt (for debugging)
  String? _reconnectionSource;

  /// Timestamp of last reconnection attempt (for debouncing)
  DateTime? _lastReconnectionAttempt;

  /// Minimum interval between reconnection attempts
  static const Duration _reconnectionDebounceInterval = Duration(milliseconds: 1000);

  /// Whether the adapter is currently waiting for wallet approval
  /// Used by lifecycle observer to know when to check for session on resume
  bool _isWaitingForApproval = false;

  /// Getter for subclasses to access approval waiting state
  bool get isWaitingForApproval => _isWaitingForApproval;

  /// Track background reconnection attempts to prevent infinite retries
  /// Reset when approval completes or is cancelled
  int _backgroundReconnectAttempts = 0;

  /// Maximum number of background reconnection attempts allowed
  /// Limits battery/resource usage while app is in background
  static const int _maxBackgroundReconnectAttempts = 3;

  /// Reset approval waiting state and background reconnection counter
  /// Call this when approval completes, is cancelled, or connection succeeds/fails
  void _resetApprovalState() {
    _isWaitingForApproval = false;
    _backgroundReconnectAttempts = 0;
  }

  /// Optimistic session check - proactively check for established sessions
  ///
  /// This method checks for valid sessions without waiting for relay events.
  /// It's called immediately when the app resumes from background, regardless
  /// of the `_isWaitingForApproval` flag status.
  ///
  /// This solves the "infinite loading" problem where:
  /// 1. User approves connection in wallet app
  /// 2. App times out while in background (relay disconnected)
  /// 3. User returns to app after timeout
  /// 4. Session exists but wasn't detected because `_isWaitingForApproval` is false
  ///
  /// By checking sessions unconditionally on resume, we can recover from
  /// timeout scenarios and provide immediate connection feedback.
  @protected
  Future<void> optimisticSessionCheck() async {
    // Skip if already connected
    if (_session != null && isConnected) {
      AppLogger.wallet('Optimistic check skipped: already connected');
      return;
    }

    // Skip if AppKit not initialized
    if (_appKit == null) {
      AppLogger.wallet('Optimistic check skipped: AppKit not initialized');
      return;
    }

    try {
      final sessions = _appKit!.sessions.getAll();

      AppLogger.wallet('🔍 Optimistic session check', data: {
        'sessionCount': sessions.length,
        'isWaitingForApproval': _isWaitingForApproval,
        'hasExistingSession': _session != null,
      });

      for (final session in sessions) {
        if (isSessionValid(session)) {
          AppLogger.wallet('✅ Optimistic Check: Valid session found!', data: {
            'topic': session.topic,
            'peer': session.peer.metadata.name,
            'accounts': session.namespaces['eip155']?.accounts.length ?? 0,
          });

          // Update session state
          _session = session;
          _parseSessionAccounts();
          _emitConnectionStatus();
          _resetApprovalState();

          AppLogger.wallet('✅ Connection recovered via optimistic check');
          return;
        }
      }

      // No valid session found - this is not an error, just informational
      if (sessions.isNotEmpty) {
        AppLogger.wallet('⚠️ Optimistic Check: Sessions exist but none valid', data: {
          'sessionCount': sessions.length,
          'sessionTopics': sessions.map((s) => s.topic.substring(0, 8)).toList(),
        });
      }
    } catch (e, stackTrace) {
      AppLogger.e('Optimistic session check failed', e, stackTrace);
    }
  }

  /// Stream of account changes from the wallet
  Stream<SessionAccounts> get accountsChangedStream => _accountsChangedController.stream;

  /// Get current session accounts
  SessionAccounts get sessionAccounts => _sessionAccounts;

  /// Get the active account address for transactions
  String? get activeAddress => _sessionAccounts.activeAccount?.address;

  /// Check if session has multiple unique addresses
  bool get hasMultipleAccounts => _sessionAccounts.hasMultipleAddresses;

  @override
  WalletType get walletType => WalletType.walletConnect;

  @override
  bool get isInitialized => _appKit != null;

  @override
  bool get isConnected => _session != null;

  @override
  String? get connectedAddress {
    // Return active account address, or first account if no active set
    if (_sessionAccounts.isNotEmpty) {
      return activeAddress ?? _sessionAccounts.accounts.first.address;
    }

    // Fallback to parsing session directly
    if (_session == null) return null;
    try {
      final namespace = _session!.namespaces['eip155'];
      if (namespace == null || namespace.accounts.isEmpty) return null;
      final account = namespace.accounts.first;
      final parts = account.split(':');
      return parts.length >= 3 ? parts[2] : null;
    } catch (e) {
      AppLogger.e('Error getting connected address', e);
      return null;
    }
  }

  @override
  int? get currentChainId {
    if (_session == null) return null;
    try {
      final namespace = _session!.namespaces['eip155'];
      if (namespace == null || namespace.accounts.isEmpty) return null;
      final account = namespace.accounts.first;
      final parts = account.split(':');
      return parts.length >= 2 ? int.tryParse(parts[1]) : null;
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<WalletConnectionStatus> get connectionStream => _connectionController.stream;

  @override
  Future<void> initialize() async {
    if (_appKit != null) return;

    AppLogger.wallet('Initializing WalletConnect adapter');

    _appKit = await ReownAppKit.createInstance(
      projectId: _config.projectId,
      metadata: PairingMetadata(
        name: _config.appName,
        description: _config.appDescription,
        url: _config.appUrl,
        icons: [_config.appIcon],
        redirect: const Redirect(
          native: '${AppConstants.deepLinkScheme}://',
          universal: 'https://${AppConstants.universalLinkHost}',
        ),
      ),
    );

    // Listen to session events
    _appKit!.onSessionConnect.subscribe(_onSessionConnect);
    _appKit!.onSessionDelete.subscribe(_onSessionDelete);
    _appKit!.onSessionEvent.subscribe(_onSessionEvent);
    _appKit!.onSessionUpdate.subscribe(_onSessionUpdate);

    // Subscribe to relay client events for connection state tracking
    // This is critical for detecting relay disconnection after cold start
    _appKit!.core.relayClient.onRelayClientConnect.subscribe(_onRelayConnect);
    _appKit!.core.relayClient.onRelayClientDisconnect.subscribe(_onRelayDisconnect);
    _appKit!.core.relayClient.onRelayClientError.subscribe(_onRelayError);

    // Check initial relay state
    _isRelayConnected = _appKit!.core.relayClient.isConnected;
    AppLogger.wallet('Initial relay state', data: {'isConnected': _isRelayConnected});

    // Restore existing sessions
    await _restoreSession();

    // Register lifecycle observer to detect app resume
    WidgetsBinding.instance.addObserver(this);

    AppLogger.wallet('WalletConnect adapter initialized');
  }

  /// Called when app lifecycle state changes (foreground/background)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Update structured logging context
    WalletLogService.instance.updateLifecycleState(state);

    AppLogger.wallet('App lifecycle state changed', data: {
      'state': state.name,
      'isWaitingForApproval': _isWaitingForApproval,
      'hasSession': _session != null,
    });

    if (state == AppLifecycleState.resumed) {
      // CRITICAL: Optimistic session check FIRST (unconditionally)
      // This handles the case where timeout occurred before resume,
      // but the wallet session was actually established.
      // Fire-and-forget - don't block lifecycle callback
      unawaited(optimisticSessionCheck());

      // Always check relay connection on resume
      // Even if not waiting for approval, relay may have disconnected
      AppLogger.wallet('App resumed, checking relay connection...');

      // Force relay state refresh to detect zombie connections
      _refreshRelayState();

      // If relay disconnected and we're in any pending state, try reconnect
      if (!_isRelayConnected && _appKit != null) {
        AppLogger.wallet('Relay disconnected on resume, forcing reconnect...');
        // Fire-and-forget reconnection - don't block lifecycle
        unawaited(_appKit!.core.relayClient.connect());
      }

      // Existing logic for waiting approval (kept for backward compatibility)
      // This provides additional session checking via relay events
      if (_isWaitingForApproval) {
        // App returned to foreground while waiting for wallet approval
        // CRITICAL: Ensure relay is connected before checking session
        _ensureRelayAndCheckSession();
      }
    }
  }

  /// Ensure relay is connected and then check for session
  ///
  /// This is the critical path for handling app resume after wallet approval.
  /// The relay WebSocket may have disconnected while app was in background,
  /// so we must reconnect before checking for session updates.
  ///
  /// Key improvements:
  /// 1. Resets _isReconnecting flag to allow fresh reconnection attempt
  /// 2. Uses longer timeout (8s) since we're now in foreground
  /// 3. Retries once if first attempt fails
  Future<void> _ensureRelayAndCheckSession() async {
    AppLogger.wallet('Ensuring relay connection before session check');

    // 1. RESET reconnection state on app resume
    //    This ensures we can retry even if a background reconnection was attempted
    //    (which would have failed due to Android network restrictions)
    _isReconnecting = false;

    // 2. Refresh relay state to detect zombie connections
    _refreshRelayState();

    // 3. Attempt relay reconnection with LONGER timeout for foreground
    //    Android allows network in foreground, so we can use longer timeout
    if (!_isRelayConnected) {
      AppLogger.wallet('Relay disconnected, attempting foreground reconnection');

      var relayReady = await ensureRelayConnected(
        timeout: const Duration(seconds: 8), // Increased from 3s
      );

      AppLogger.wallet('Relay reconnection on resume (attempt 1)', data: {
        'success': relayReady,
      });

      // 4. If first attempt fails, retry once more after short delay
      if (!relayReady) {
        AppLogger.wallet('First reconnection failed, retrying after 500ms...');
        await Future.delayed(const Duration(milliseconds: 500));

        relayReady = await ensureRelayConnected(
          timeout: const Duration(seconds: 5),
        );

        AppLogger.wallet('Relay reconnection on resume (attempt 2)', data: {
          'success': relayReady,
        });
      }

      if (!relayReady) {
        AppLogger.wallet(
          'Relay reconnection failed after retries, checking session anyway...',
        );
      }
    }

    // 5. Check for session
    await checkConnectionOnResume();
  }

  /// Protected method for subclasses to check connection on resume
  /// This allows subclasses to call this directly without going through
  /// lifecycle methods, avoiding duplicate triggers.
  @protected
  Future<void> checkConnectionOnResume() async {
    AppLogger.wallet('Checking connection after app resume');

    // 0. Refresh relay state to detect zombie connections
    final relayActuallyConnected = _refreshRelayState();
    if (!relayActuallyConnected) {
      AppLogger.wallet('Relay not actually connected, session sync may be delayed');
    }

    // 1. Session already established - clear flag and return
    if (_session != null) {
      AppLogger.wallet('Session already established, clearing approval flag');
      _resetApprovalState();
      return;
    }

    // 2. AppKit not initialized - can't check
    if (_appKit == null) {
      AppLogger.wallet('AppKit not initialized, skipping check');
      return;
    }

    // 3. Check if AppKit has received a session while we were in background
    final sessions = _appKit!.sessions.getAll();
    for (final session in sessions) {
      if (isSessionValid(session)) {
        AppLogger.wallet('Found valid session after resume', data: {
          'topic': session.topic,
          'peerName': session.peer.metadata.name,
          'relayConnected': relayActuallyConnected,
        });

        // Update session and emit status
        // Note: The session.future in connect() may still be waiting,
        // but _onSessionConnect event will also trigger when it resolves
        _session = session;
        _parseSessionAccounts();
        _emitConnectionStatus();
        // Clear flag AFTER emitting status to ensure connection completes
        _resetApprovalState();
        return;
      }
    }

    // 4. No session found yet - continue waiting for timeout
    // Do NOT clear _isWaitingForApproval here - we need to keep checking
    AppLogger.wallet('No session found after resume, continuing to wait', data: {
      'relayConnected': relayActuallyConnected,
      'sessionCount': sessions.length,
    });
  }

  // ============================================================
  // Relay Connection Management
  // ============================================================

  /// Handle relay client connect event
  void _onRelayConnect(dynamic _) {
    _isRelayConnected = true;
    AppLogger.wallet('Relay client connected');

    // Update structured logging
    WalletLogService.instance.updateRelayState(RelayState.connected);
    WalletLogService.instance.logRelayEvent('connected');
  }

  /// Handle relay client disconnect event
  void _onRelayDisconnect(dynamic _) {
    _isRelayConnected = false;
    AppLogger.wallet('Relay client disconnected');

    // Update structured logging
    WalletLogService.instance.updateRelayState(RelayState.disconnected);
    WalletLogService.instance.logRelayEvent('disconnected');
  }

  /// Handle relay client error event
  ///
  /// When an error occurs while waiting for wallet approval, we schedule
  /// an automatic reconnection attempt to recover the connection.
  ///
  /// CRITICAL: This handler MUST update _isRelayConnected to false immediately.
  /// Without this, ensureRelayConnected() will return true based on stale cached state,
  /// preventing reconnection attempts and causing session sync failures.
  void _onRelayError(dynamic event) {
    // Extract detailed error information if available
    String errorMessage = 'Unknown error';
    try {
      if (event != null) {
        errorMessage = event.toString();
      }
    } catch (e) {
      errorMessage = 'Error extracting message: $e';
    }

    AppLogger.wallet('Relay client error', data: {
      'error': errorMessage,
      'isWaitingForApproval': _isWaitingForApproval,
      'isReconnecting': _isReconnecting,
      'wasRelayConnected': _isRelayConnected,
    });

    // Update structured logging with error details
    WalletLogService.instance.updateRelayState(
      RelayState.error,
      errorMessage: errorMessage,
    );
    WalletLogService.instance.logRelayEvent(
      'error',
      errorMessage: errorMessage,
      isReconnection: _isReconnecting,
    );

    // CRITICAL FIX: Update relay state immediately on error
    // This prevents "zombie state" where cached state is true but relay is disconnected
    _isRelayConnected = false;

    // If we're waiting for wallet approval, schedule reconnection
    if (_isWaitingForApproval && !_isReconnecting) {
      _scheduleRelayReconnect();
    }
  }

  /// Schedule a relay reconnection attempt
  ///
  /// Uses a short delay to avoid immediate retry storms.
  /// Only one reconnection can be in progress at a time.
  ///
  /// IMPORTANT: Background reconnection policy:
  /// - If NOT waiting for approval: Skip reconnection (handled on resume)
  /// - If waiting for approval: Allow limited reconnection (max 3 attempts)
  ///   This ensures wallet approval events are received even when app is backgrounded
  void _scheduleRelayReconnect() {
    if (_isReconnecting) {
      AppLogger.wallet('Relay reconnection already in progress, skipping');
      return;
    }

    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    final isBackground = lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.inactive;

    // Background handling with approval-aware logic
    if (isBackground) {
      // Case 1: Not waiting for approval - skip reconnection
      if (!_isWaitingForApproval) {
        AppLogger.wallet(
          'Skipping reconnection while in background (state: ${lifecycleState?.name})',
          data: {'reason': 'Not waiting for approval, will reconnect on resume'},
        );
        return;
      }

      // Case 2: Waiting for approval - allow limited reconnection
      if (_backgroundReconnectAttempts >= _maxBackgroundReconnectAttempts) {
        AppLogger.wallet(
          'Max background reconnection attempts reached',
          data: {
            'attempts': _backgroundReconnectAttempts,
            'max': _maxBackgroundReconnectAttempts,
            'state': lifecycleState?.name,
          },
        );
        return;
      }

      _backgroundReconnectAttempts++;
      AppLogger.wallet(
        'Background reconnection ALLOWED (waiting for approval)',
        data: {
          'attempt': _backgroundReconnectAttempts,
          'max': _maxBackgroundReconnectAttempts,
          'state': lifecycleState?.name,
        },
      );
    }

    _isReconnecting = true;
    AppLogger.wallet('Scheduling relay reconnection in 500ms');

    // Update structured logging
    WalletLogService.instance.updateRelayState(
      RelayState.reconnecting,
      isReconnecting: true,
    );

    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        final success = await ensureRelayConnected(
          timeout: const Duration(seconds: 10),
        );
        AppLogger.wallet('Scheduled relay reconnection result', data: {
          'success': success,
        });

        // Update logging based on result
        if (success) {
          WalletLogService.instance.logRelayEvent(
            'reconnection_success',
            isReconnection: true,
          );
        } else {
          WalletLogService.instance.logRelayEvent(
            'reconnection_failed',
            isReconnection: true,
          );
        }
      } catch (e) {
        AppLogger.wallet('Scheduled relay reconnection failed', data: {
          'error': e.toString(),
        });
        WalletLogService.instance.logRelayEvent(
          'reconnection_error',
          errorMessage: e.toString(),
          isReconnection: true,
        );
      } finally {
        _isReconnecting = false;
        _reconnectionSource = null;
      }
    });
  }

  /// Attempt reconnection with debouncing and source tracking
  ///
  /// This method provides a unified entry point for all reconnection attempts,
  /// preventing race conditions from multiple sources (app resume, relay error, timeout).
  ///
  /// [source] identifies where the reconnection was triggered from (for debugging)
  /// Returns true if reconnection was successful, false if skipped or failed
  Future<bool> attemptDebouncedReconnection({
    required String source,
    Duration? timeout,
  }) async {
    final now = DateTime.now();

    // Check debounce interval - skip if too recent
    if (_lastReconnectionAttempt != null) {
      final elapsed = now.difference(_lastReconnectionAttempt!);
      if (elapsed < _reconnectionDebounceInterval) {
        AppLogger.wallet('Reconnection debounced', data: {
          'source': source,
          'elapsedMs': elapsed.inMilliseconds,
          'debounceMs': _reconnectionDebounceInterval.inMilliseconds,
        });
        return false;
      }
    }

    // Check if already reconnecting
    if (_isReconnecting) {
      AppLogger.wallet('Reconnection already in progress', data: {
        'source': source,
        'currentSource': _reconnectionSource,
      });
      return false;
    }

    _isReconnecting = true;
    _reconnectionSource = source;
    _lastReconnectionAttempt = now;

    try {
      AppLogger.wallet('Starting debounced reconnection', data: {
        'source': source,
        'timeout': timeout?.inSeconds ?? 10,
      });

      final success = await ensureRelayConnected(
        timeout: timeout ?? const Duration(seconds: 10),
      );

      AppLogger.wallet('Debounced reconnection result', data: {
        'source': source,
        'success': success,
      });

      return success;
    } finally {
      _isReconnecting = false;
      _reconnectionSource = null;
    }
  }

  /// Check if relay is currently connected
  bool get isRelayConnected => _isRelayConnected;

  /// Refresh relay connection state from actual source
  ///
  /// This detects "zombie connections" where our cached state says connected
  /// but the actual WebSocket is disconnected.
  bool _refreshRelayState() {
    if (_appKit == null) return false;

    final actualState = _appKit!.core.relayClient.isConnected;

    // Detect state mismatch (zombie connection)
    if (_isRelayConnected != actualState) {
      AppLogger.wallet('Relay state mismatch detected', data: {
        'cached': _isRelayConnected,
        'actual': actualState,
      });
      _isRelayConnected = actualState;
    }

    return actualState;
  }

  /// Ensure relay is connected, attempting reconnection if needed.
  ///
  /// Returns true if relay is connected, false if reconnection failed.
  ///
  /// This is CRITICAL after cold start when the WebSocket connection
  /// was lost due to Android process death. Without relay reconnection,
  /// stored sessions appear valid but cannot communicate with the wallet.
  Future<bool> ensureRelayConnected({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_appKit == null) {
      AppLogger.wallet('Cannot reconnect relay: AppKit not initialized');
      return false;
    }

    // Defensive check: Skip if adapter is disposed
    // This prevents StateError when StreamController is already closed
    if (_connectionController.isClosed) {
      AppLogger.wallet('Cannot reconnect relay: adapter already disposed');
      return false;
    }

    // Already connected
    if (_isRelayConnected) {
      AppLogger.wallet('Relay already connected');
      return true;
    }

    AppLogger.wallet('Relay not connected, attempting reconnection...');

    final completer = Completer<bool>();
    Timer? timeoutTimer;

    void onConnect(dynamic _) {
      if (!completer.isCompleted) {
        AppLogger.wallet('Relay reconnection successful');
        completer.complete(true);
        timeoutTimer?.cancel();
      }
    }

    void onError(dynamic event) {
      if (!completer.isCompleted) {
        AppLogger.wallet('Relay reconnection error', data: {'error': event?.toString()});
        // Don't complete on error - wait for timeout or success
      }
    }

    // Subscribe to connection events for this reconnection attempt
    _appKit!.core.relayClient.onRelayClientConnect.subscribe(onConnect);
    _appKit!.core.relayClient.onRelayClientError.subscribe(onError);

    try {
      // Attempt to reconnect relay
      await _appKit!.core.relayClient.connect();

      // Set timeout for reconnection
      timeoutTimer = Timer(timeout, () {
        if (!completer.isCompleted) {
          AppLogger.wallet('Relay reconnection timed out after ${timeout.inSeconds}s');
          completer.complete(false);
        }
      });

      return await completer.future;
    } catch (e) {
      AppLogger.wallet('Relay reconnection exception', data: {'error': e.toString()});
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      return false;
    } finally {
      // Cleanup subscriptions for this attempt
      _appKit!.core.relayClient.onRelayClientConnect.unsubscribe(onConnect);
      _appKit!.core.relayClient.onRelayClientError.unsubscribe(onError);
      timeoutTimer?.cancel();
    }
  }

  // ============================================================
  // Session Validation
  // ============================================================

  /// Check if a session matches the expected wallet type.
  /// Subclasses should override this to filter sessions by wallet name.
  bool isSessionValid(SessionData session) {
    return true; // Default: accept any session
  }

  Future<void> _restoreSession() async {
    final sessions = _appKit!.sessions.getAll();

    if (sessions.isEmpty) {
      AppLogger.wallet('No sessions to restore');
      return;
    }

    AppLogger.wallet('Found ${sessions.length} stored sessions, checking relay...');

    // CRITICAL: Ensure relay is connected before using stored sessions
    // After cold start (Android process death), the WebSocket connection is dead
    // even though session objects are restored from storage. Without relay
    // reconnection, sessions appear valid but cannot communicate with the wallet,
    // causing infinite approval loops.
    final relayConnected = await ensureRelayConnected();

    if (!relayConnected) {
      AppLogger.wallet('Relay not connected, keeping sessions for later restoration', data: {
        'sessionCount': sessions.length,
      });
      // DO NOT clear sessions here!
      // Sessions should be preserved for later restoration attempts.
      // The relay connection will be retried in restoreSessionByTopic()
      // or when the user manually triggers a reconnection.
      // Clearing sessions on temporary network issues causes permanent data loss.
      return;
    }

    // Relay is connected, proceed with session restoration
    for (final session in sessions) {
      if (isSessionValid(session)) {
        _session = session;
        _parseSessionAccounts();
        _emitConnectionStatus();

        AppLogger.wallet('Session restored successfully', data: {
          'address': connectedAddress,
          'accountCount': _sessionAccounts.count,
          'topic': _session!.topic,
          'peerName': _session!.peer.metadata.name,
          'relayConnected': _isRelayConnected,
        });
        return; // Stop after finding the first valid session
      }
    }

    if (sessions.isNotEmpty && _session == null) {
      AppLogger.wallet('Found ${sessions.length} sessions but none matched validation');
    }
  }

  void _onSessionConnect(SessionConnect? event) {
    if (event != null) {
      _session = event.session;
      _parseSessionAccounts();
      _emitConnectionStatus();

      // Update structured logging
      WalletLogService.instance.updateSessionState(
        WcSessionState.approved,
        sessionTopic: event.session.topic,
        peerName: event.session.peer.metadata.name,
      );
      WalletLogService.instance.logSessionEvent(
        'connected',
        topic: event.session.topic,
        peerName: event.session.peer.metadata.name,
        namespaces: event.session.namespaces.keys.toList(),
        accountCount: _sessionAccounts.count,
      );

      AppLogger.wallet('Session connected', data: {
        'address': connectedAddress,
        'accountCount': _sessionAccounts.count,
        'hasMultipleAccounts': hasMultipleAccounts,
      });
    }
  }

  void _onSessionDelete(SessionDelete? event) {
    // Update structured logging before clearing session
    WalletLogService.instance.updateSessionState(WcSessionState.deleted);
    WalletLogService.instance.logSessionEvent(
      'deleted',
      topic: event?.topic,
    );

    _session = null;
    _sessionAccounts = const SessionAccounts.empty();
    _requestedChainId = null;
    _connectionController.add(WalletConnectionStatus.disconnected());
    AppLogger.wallet('Session deleted');
  }

  /// Handle session events like accountsChanged and chainChanged
  void _onSessionEvent(SessionEvent? event) {
    if (event == null) return;

    // Log session event in structured format
    WalletLogService.instance.logSessionEvent(
      event.name,
      topic: event.topic,
      extra: {'data': event.data?.toString()},
    );

    AppLogger.wallet('Session event received', data: {
      'name': event.name,
      'topic': event.topic,
    });

    switch (event.name) {
      case 'accountsChanged':
        _handleAccountsChanged(event.data);
        break;
      case 'chainChanged':
        _handleChainChanged(event.data);
        break;
      default:
        AppLogger.wallet('Unhandled session event: ${event.name}');
    }
  }

  /// Handle session update (namespace changes)
  void _onSessionUpdate(SessionUpdate? event) {
    if (event == null) return;

    // Log session update in structured format
    WalletLogService.instance.logSessionEvent(
      'update',
      topic: event.topic,
      namespaces: event.namespaces.keys.toList(),
    );

    AppLogger.wallet('Session update received', data: {
      'topic': event.topic,
    });

    // Re-parse accounts from updated namespaces
    if (_session != null && _session!.topic == event.topic) {
      // Update session with new namespaces
      _session = _appKit!.sessions.get(event.topic);
      _parseSessionAccounts();
      _accountsChangedController.add(_sessionAccounts);
      _emitConnectionStatus();
    }
  }

  /// Handle accountsChanged event from wallet
  void _handleAccountsChanged(dynamic data) {
    AppLogger.wallet('Accounts changed', data: {'data': data});

    if (data is List) {
      // Data is typically a list of account strings
      final accountStrings = data.map((e) => e.toString()).toList();

      // Check if these are CAIP-10 format or just addresses
      if (accountStrings.isNotEmpty && accountStrings.first.contains(':')) {
        // CAIP-10 format
        _sessionAccounts = _sessionAccounts.updateAccounts(accountStrings);
      } else {
        // Just addresses - need to get full accounts from session
        _parseSessionAccounts();
      }

      _accountsChangedController.add(_sessionAccounts);
      _emitConnectionStatus();
    }
  }

  /// Handle chainChanged event from wallet
  void _handleChainChanged(dynamic data) {
    AppLogger.wallet('Chain changed', data: {'data': data});
    // Re-emit connection status with updated chain
    _emitConnectionStatus();
  }

  /// Parse accounts from current session namespaces
  void _parseSessionAccounts() {
    if (_session == null) {
      _sessionAccounts = const SessionAccounts.empty();
      return;
    }

    try {
      final namespace = _session!.namespaces['eip155'];
      if (namespace == null || namespace.accounts.isEmpty) {
        _sessionAccounts = const SessionAccounts.empty();
        return;
      }

      _sessionAccounts = SessionAccounts.fromNamespaceAccounts(namespace.accounts);

      AppLogger.wallet('Parsed session accounts', data: {
        'count': _sessionAccounts.count,
        'uniqueAddresses': _sessionAccounts.uniqueAddresses.length,
        'activeAddress': _sessionAccounts.activeAddress,
      });
    } catch (e) {
      AppLogger.e('Error parsing session accounts', e);
      _sessionAccounts = const SessionAccounts.empty();
    }
  }

  void _emitConnectionStatus() {
    if (_session != null && connectedAddress != null) {
      final wallet = WalletEntity(
        address: connectedAddress!,
        type: walletType,
        chainId: _requestedChainId ?? currentChainId,
        sessionTopic: _session!.topic,
        connectedAt: DateTime.now(),
        metadata: {
          'sessionAccounts': _sessionAccounts.accounts.map((a) => a.caip10Id).toList(),
          'hasMultipleAccounts': hasMultipleAccounts,
        },
      );
      _connectionController.add(WalletConnectionStatus.connected(wallet));
    }
  }

  /// Set the active account for transactions.
  ///
  /// The address must be one of the accounts approved in the session.
  /// Returns true if successful, false if address is not in session.
  bool setActiveAccount(String address) {
    if (!_sessionAccounts.containsAddress(address)) {
      AppLogger.w(
        'Cannot set active account: $address not in session. '
        'Available: ${_sessionAccounts.uniqueAddresses}',
      );
      return false;
    }

    _sessionAccounts = _sessionAccounts.setActiveAddress(address);
    _accountsChangedController.add(_sessionAccounts);
    _emitConnectionStatus();

    AppLogger.wallet('Active account changed', data: {
      'newActiveAddress': address,
    });

    return true;
  }

  /// Get all session accounts (for UI display)
  SessionAccounts getSessionAccounts() => _sessionAccounts;

  /// Prepare connection by generating URI without waiting for session approval.
  ///
  /// This is useful for wallet adapters that need to:
  /// 1. Generate the WalletConnect URI
  /// 2. Open the wallet app with the URI
  /// 3. Then wait for session approval
  ///
  /// Returns a [Future] that completes with [WalletEntity] when the session is approved.
  /// The URI can be retrieved via [getConnectionUri()] after this method returns.
  ///
  /// Uses a Watchdog Timer pattern to detect sessions even when the
  /// onSessionConnect event is missed (e.g., when app is in background).
  ///
  /// Throws [WalletException] if connection fails.
  Future<Future<WalletEntity>> prepareConnection({int? chainId}) async {
    AppLogger.wallet('🔵 prepareConnection START', data: {
      'chainId': chainId,
      'hasExistingSession': _session != null,
      'existingSessionTopic': _session?.topic,
      'isInitialized': isInitialized,
    });

    if (!isInitialized) {
      await initialize();
    }

    final targetChainId = chainId ?? 1;
    _requestedChainId = targetChainId;

    // Mark that we're waiting for approval
    _isWaitingForApproval = true;

    _connectionController.add(WalletConnectionStatus.connecting(
      message: 'Initializing connection...',
      retryCount: 0,
      maxRetries: 1,
    ));

    AppLogger.wallet('🔵 prepareConnection: about to call _appKit.connect()', data: {
      'targetChainId': targetChainId,
    });

    // Create namespace (optional only; required is deprecated)
    final optionalChainIds = {
      ..._config.supportedChainIds,
      targetChainId,
    };

    final optionalNamespaces = {
      'eip155': RequiredNamespace(
        chains: optionalChainIds.map((id) => 'eip155:$id').toList(),
        methods: _config.supportedMethods,
        events: _config.supportedEvents,
      ),
    };

    // Store initial session topics to detect new sessions
    final initialSessionTopics = _appKit!.sessions.getAll().map((s) => s.topic).toSet();

    // Create connect response - this generates the URI
    AppLogger.wallet('🔵 prepareConnection: calling _appKit!.connect() NOW');
    final connectResponse = await _appKit!.connect(
      optionalNamespaces: optionalNamespaces,
    );
    AppLogger.wallet('🔵 prepareConnection: _appKit!.connect() RETURNED');

    _uri = connectResponse.uri?.toString();

    AppLogger.wallet('🔵 prepareConnection: URI generated', data: {
      'hasUri': _uri != null,
      'uriPrefix': _uri?.substring(0, _uri!.length.clamp(0, 50)),
    });

    _connectionController.add(WalletConnectionStatus.connecting(
      message: 'Waiting for wallet approval...',
      retryCount: 0,
      maxRetries: 1,
    ));

    // ★ Watchdog Pattern: Use Completer to handle both event-based and polling-based session detection
    final sessionCompleter = Completer<SessionData>();
    Timer? watchdogTimer;

    // 1. Event-based listener (original session.future)
    // We intentionally don't await this - it runs in parallel with the watchdog
    unawaited(connectResponse.session.future.then((session) {
      if (!sessionCompleter.isCompleted) {
        AppLogger.wallet('⚡ Session received via event', data: {
          'topic': session.topic.substring(0, 10),
          'peerName': session.peer.metadata.name,
        });
        sessionCompleter.complete(session);
      }
    }).catchError((e) {
      if (!sessionCompleter.isCompleted) {
        AppLogger.wallet('❌ Session event error', data: {'error': e.toString()});
        sessionCompleter.completeError(e);
      }
    }));

    // 2. Watchdog Timer: Poll for new sessions every second
    // This catches sessions that arrive while app is in background
    // and the event listener missed the onSessionConnect event
    watchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (sessionCompleter.isCompleted) {
        timer.cancel();
        return;
      }

      final currentSessions = _appKit!.sessions.getAll();
      for (final session in currentSessions) {
        // Check if this is a NEW session (not in initial set) and valid for this wallet type
        if (!initialSessionTopics.contains(session.topic) && isSessionValid(session)) {
          AppLogger.wallet('🔍 Watchdog found new session!', data: {
            'topic': session.topic.substring(0, 10),
            'peerName': session.peer.metadata.name,
            'initialCount': initialSessionTopics.length,
            'currentCount': currentSessions.length,
          });
          timer.cancel();
          if (!sessionCompleter.isCompleted) {
            sessionCompleter.complete(session);
          }
          return;
        }
      }
    });

    // Return a future that completes when session is approved (via event OR watchdog)
    return sessionCompleter.future.then<WalletEntity>((session) {
      // Clean up watchdog timer
      watchdogTimer?.cancel();

      _session = session;
      _parseSessionAccounts();

      if (connectedAddress == null) {
        throw const WalletException(
          message: 'Failed to get connected address',
          code: 'NO_ADDRESS',
        );
      }

      final wallet = WalletEntity(
        address: connectedAddress!,
        type: walletType,
        chainId: _requestedChainId ?? currentChainId,
        sessionTopic: _session!.topic,
        connectedAt: DateTime.now(),
        metadata: {
          'sessionAccounts': _sessionAccounts.accounts.map((a) => a.caip10Id).toList(),
          'hasMultipleAccounts': hasMultipleAccounts,
          'uniqueAddressCount': _sessionAccounts.uniqueAddresses.length,
        },
      );

      _connectionController.add(WalletConnectionStatus.connected(wallet));
      _resetApprovalState();

      AppLogger.wallet('Wallet connected via prepareConnection', data: {
        'address': wallet.address,
        'chainId': wallet.chainId,
      });

      return wallet;
    });
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    if (!isInitialized) {
      await initialize();
    }

    final targetChainId = chainId ?? 1; // Default to Ethereum mainnet
    _requestedChainId = targetChainId; // Store for WalletEntity creation
    const maxRetries = AppConstants.maxConnectionRetries;
    int retryCount = 0;

    // Mark that we're waiting for approval - enables lifecycle resume check
    _isWaitingForApproval = true;

    _connectionController.add(WalletConnectionStatus.connecting(
      message: 'Initializing connection...',
      retryCount: 0,
      maxRetries: maxRetries,
    ));

    while (retryCount < maxRetries) {
      Timer? watchdogTimer;

      try {
        // Create namespace (optional only; required is deprecated)
        final optionalChainIds = {
          ..._config.supportedChainIds,
          targetChainId,
        };

        final optionalNamespaces = {
          'eip155': RequiredNamespace(
            chains: optionalChainIds.map((id) => 'eip155:$id').toList(),
            methods: _config.supportedMethods,
            events: _config.supportedEvents,
          ),
        };

        // Store initial session topics to detect new sessions
        final initialSessionTopics = _appKit!.sessions.getAll().map((s) => s.topic).toSet();

        // Create connect response
        final connectResponse = await _appKit!.connect(
          optionalNamespaces: optionalNamespaces,
        );

        _uri = connectResponse.uri?.toString();

        AppLogger.wallet('Connection URI generated', data: {
          'uri': _uri,
          'attempt': retryCount + 1,
        });

        _connectionController.add(WalletConnectionStatus.connecting(
          message: 'Waiting for wallet approval...',
          retryCount: retryCount,
          maxRetries: maxRetries,
        ));

        // ★ Watchdog Pattern: Use Completer to handle both event-based and polling-based session detection
        final sessionCompleter = Completer<SessionData>();

        // 1. Event-based listener (original session.future)
        // We intentionally don't await this - it runs in parallel with the watchdog
        unawaited(connectResponse.session.future.then((session) {
          if (!sessionCompleter.isCompleted) {
            AppLogger.wallet('⚡ Session received via event (connect)', data: {
              'topic': session.topic.substring(0, 10),
              'peerName': session.peer.metadata.name,
            });
            sessionCompleter.complete(session);
          }
        }).catchError((e) {
          if (!sessionCompleter.isCompleted) {
            AppLogger.wallet('❌ Session event error (connect)', data: {'error': e.toString()});
            sessionCompleter.completeError(e);
          }
        }));

        // 2. Watchdog Timer: Poll for new sessions every second
        watchdogTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (sessionCompleter.isCompleted) {
            timer.cancel();
            return;
          }

          final currentSessions = _appKit!.sessions.getAll();
          for (final session in currentSessions) {
            // Check if this is a NEW session and valid for this wallet type
            if (!initialSessionTopics.contains(session.topic) && isSessionValid(session)) {
              AppLogger.wallet('🔍 Watchdog found new session! (connect)', data: {
                'topic': session.topic.substring(0, 10),
                'peerName': session.peer.metadata.name,
                'attempt': retryCount + 1,
              });
              timer.cancel();
              if (!sessionCompleter.isCompleted) {
                sessionCompleter.complete(session);
              }
              return;
            }
          }
        });

        // Wait for session approval with timeout
        _session = await sessionCompleter.future.timeout(
          AppConstants.connectionTimeout,
          onTimeout: () {
            watchdogTimer?.cancel();
            throw WalletException(
              message: 'Connection timed out after ${AppConstants.connectionTimeout.inSeconds}s',
              code: 'TIMEOUT',
            );
          },
        );

        // Clean up watchdog timer on success
        watchdogTimer.cancel();

        // Parse accounts from the approved session
        _parseSessionAccounts();

        if (connectedAddress == null) {
          throw const WalletException(
            message: 'Failed to get connected address',
            code: 'NO_ADDRESS',
          );
        }

        final wallet = WalletEntity(
          address: connectedAddress!,
          type: walletType,
          chainId: _requestedChainId ?? currentChainId,
          sessionTopic: _session!.topic,
          connectedAt: DateTime.now(),
          metadata: {
            'sessionAccounts': _sessionAccounts.accounts.map((a) => a.caip10Id).toList(),
            'hasMultipleAccounts': hasMultipleAccounts,
            'uniqueAddressCount': _sessionAccounts.uniqueAddresses.length,
          },
        );

        _connectionController.add(WalletConnectionStatus.connected(wallet));

        // Connection successful - clear waiting flag
        _resetApprovalState();

        AppLogger.wallet('Wallet connected', data: {
          'address': wallet.address,
          'chainId': wallet.chainId,
          'requestedChainId': _requestedChainId,
          'sessionChainId': currentChainId,
          'attempts': retryCount + 1,
          'accountCount': _sessionAccounts.count,
          'hasMultipleAccounts': hasMultipleAccounts,
        });

        return wallet;

      } on WalletException catch (e) {
        watchdogTimer?.cancel();
        retryCount++;
        AppLogger.w('Connection attempt $retryCount failed: ${e.message}');

        // Debug: Log retry condition evaluation
        final willRetry = e.code == 'TIMEOUT' && retryCount < maxRetries;
        AppLogger.wallet('Retry evaluation', data: {
          'errorCode': e.code,
          'retryCount': retryCount,
          'maxRetries': maxRetries,
          'willRetry': willRetry,
        });

        if (willRetry) {
          // Emit retry status
          _connectionController.add(WalletConnectionStatus.connecting(
            message: 'Retrying connection ($retryCount/$maxRetries)...',
            retryCount: retryCount,
            maxRetries: maxRetries,
          ));
          await Future.delayed(AppConstants.connectionRetryDelay);
          continue;
        }

        // Final failure - clear waiting flag
        _resetApprovalState();
        AppLogger.e('Connection failed after $retryCount attempt(s)', e);
        _connectionController.add(WalletConnectionStatus.error(e.message));
        rethrow;

      } catch (e) {
        // Unexpected error - clean up and clear waiting flag
        watchdogTimer?.cancel();
        _resetApprovalState();
        AppLogger.e('Unexpected connection error', e);
        _connectionController.add(WalletConnectionStatus.error(e.toString()));
        rethrow;
      }
    }

    // Max retries exceeded - clear waiting flag
    _resetApprovalState();
    const exception = WalletException(
      message: 'Max connection retries exceeded',
      code: 'MAX_RETRIES',
    );
    _connectionController.add(WalletConnectionStatus.error(exception.message));
    throw exception;
  }

  @override
  Future<String?> getConnectionUri() async {
    return _uri;
  }

  /// Get the current session topic for persistence
  ///
  /// Returns null if no session is currently active.
  String? getSessionTopic() {
    return _session?.topic;
  }

  /// Restore session by topic for app restart recovery
  ///
  /// This method is called when the app restarts and we have a persisted
  /// session topic. It attempts to find and restore the session.
  ///
  /// Returns the connected WalletEntity if successful, null otherwise.
  Future<WalletEntity?> restoreSessionByTopic(String sessionTopic) async {
    if (_appKit == null) {
      AppLogger.wallet('restoreSessionByTopic: AppKit not initialized');
      return null;
    }

    AppLogger.wallet('Attempting to restore session by topic', data: {
      'sessionTopic': sessionTopic.substring(0, 10),
    });

    // First ensure relay is connected with longer timeout for cold start
    // Cold start may require more time for WebSocket connection
    final relayConnected = await ensureRelayConnected(
      timeout: const Duration(seconds: 10),
    );
    if (!relayConnected) {
      AppLogger.wallet('restoreSessionByTopic: Relay not connected after extended timeout');
      return null;
    }

    // Find the session with matching topic
    final sessions = _appKit!.sessions.getAll();
    final targetSession = sessions.where((s) => s.topic == sessionTopic).firstOrNull;

    if (targetSession == null) {
      AppLogger.wallet('Session not found in AppKit storage', data: {
        'requestedTopic': sessionTopic.substring(0, 10),
        'availableSessions': sessions.length,
        'availableTopics': sessions.map((s) => s.topic.substring(0, 10)).toList(),
      });
      return null;
    }

    // Validate the session
    if (!isSessionValid(targetSession)) {
      AppLogger.wallet('Session found but invalid', data: {
        'sessionTopic': sessionTopic.substring(0, 10),
      });
      return null;
    }

    // Session is valid, restore it
    _session = targetSession;
    _parseSessionAccounts();
    _emitConnectionStatus();

    AppLogger.wallet('Session restored by topic successfully', data: {
      'address': connectedAddress,
      'accountCount': _sessionAccounts.count,
      'topic': _session!.topic.substring(0, 10),
      'peerName': _session!.peer.metadata.name,
    });

    // Build and return the WalletEntity
    if (connectedAddress == null) {
      return null;
    }

    return WalletEntity(
      address: connectedAddress!,
      type: walletType,
      chainId: currentChainId,
      sessionTopic: _session!.topic,
      connectedAt: DateTime.now(),
    );
  }

  /// Clear all previous WalletConnect pairings and sessions.
  ///
  /// This should be called before establishing a new connection to ensure
  /// clean state, especially when switching between different wallet apps.
  /// This prevents issues where stale session data from a previous wallet
  /// (e.g., Phantom) could interfere with a new connection (e.g., Trust Wallet).
  Future<void> clearPreviousSessions() async {
    if (_appKit == null) {
      AppLogger.wallet('clearPreviousSessions: AppKit not initialized, skipping');
      return;
    }

    try {
      // Clear any existing sessions
      final sessions = _appKit!.sessions.getAll();
      AppLogger.wallet('🔴 clearPreviousSessions: clearing sessions', data: {
        'sessionCount': sessions.length,
      });

      for (final session in sessions) {
        try {
          await _appKit!.disconnectSession(
            topic: session.topic,
            reason: const ReownSignError(
              code: 6000,
              message: 'Clearing previous sessions for new connection',
            ),
          );
          AppLogger.wallet('🔴 Disconnected session', data: {
            'topic': session.topic.substring(0, 10),
            'peerName': session.peer.metadata.name,
          });
        } catch (e) {
          AppLogger.d('Failed to disconnect session: ${session.topic}');
        }
      }

      // Clear any existing pairings
      final pairings = _appKit!.core.pairing.getStore().getAll();
      AppLogger.wallet('🔴 clearPreviousSessions: clearing pairings', data: {
        'pairingCount': pairings.length,
      });

      for (final pairing in pairings) {
        try {
          await _appKit!.core.pairing.disconnect(topic: pairing.topic);
          AppLogger.wallet('🔴 Disconnected pairing', data: {
            'topic': pairing.topic.substring(0, 10),
          });
        } catch (e) {
          AppLogger.d('Failed to disconnect pairing: ${pairing.topic}');
        }
      }

      // Clear local state
      _session = null;
      _uri = null;
      _sessionAccounts = const SessionAccounts.empty();

      AppLogger.wallet('🔴 clearPreviousSessions: completed');
    } catch (e) {
      AppLogger.e('Error clearing previous sessions', e);
    }
  }

  @override
  Future<void> disconnect() async {
    if (_session == null) return;

    try {
      await _appKit!.disconnectSession(
        topic: _session!.topic,
        reason: const ReownSignError(
          code: 6000,
          message: 'User disconnected',
        ),
      );
    } catch (e) {
      AppLogger.e('Error disconnecting', e);
    } finally {
      _session = null;
      _uri = null;
      _requestedChainId = null;
      _connectionController.add(WalletConnectionStatus.disconnected());
    }
  }

  @override
  Future<void> switchChain(int chainId) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:$chainId',
        request: SessionRequestParams(
          method: 'wallet_switchEthereumChain',
          params: [
            {'chainId': '0x${chainId.toRadixString(16)}'}
          ],
        ),
      );
    } catch (e) {
      AppLogger.e('Error switching chain', e);
      rethrow;
    }
  }

  @override
  Future<String> sendTransaction(TransactionRequest request) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      final result = await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${request.chainId}',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [request.toJson()],
        ),
      );

      AppLogger.tx('Transaction sent', txHash: result as String);
      return result;
    } catch (e) {
      AppLogger.e('Error sending transaction', e);
      rethrow;
    }
  }

  @override
  Future<String> personalSign(String message, String address) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      final result = await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${currentChainId ?? 1}',
        request: SessionRequestParams(
          method: 'personal_sign',
          params: [message, address],
        ),
      );

      AppLogger.wallet('Message signed', data: {'address': address});
      return result as String;
    } catch (e) {
      AppLogger.e('Error signing message', e);
      rethrow;
    }
  }

  @override
  Future<String> signTypedData(
    String address,
    Map<String, dynamic> typedData,
  ) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      final result = await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${currentChainId ?? 1}',
        request: SessionRequestParams(
          method: 'eth_signTypedData_v4',
          params: [address, typedData],
        ),
      );

      AppLogger.wallet('Typed data signed', data: {'address': address});
      return result as String;
    } catch (e) {
      AppLogger.e('Error signing typed data', e);
      rethrow;
    }
  }

  @override
  Future<List<String>> getAccounts() async {
    if (_session == null) return [];
    final namespace = _session!.namespaces['eip155'];
    if (namespace == null) return [];
    return namespace.accounts
        .map((account) => account.split(':').last)
        .toList();
  }

  @override
  Future<int> getChainId() async {
    return currentChainId ?? 1;
  }

  @override
  Future<void> addChain({
    required int chainId,
    required String chainName,
    required String rpcUrl,
    required String symbol,
    required int decimals,
    String? explorerUrl,
  }) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${currentChainId ?? 1}',
        request: SessionRequestParams(
          method: 'wallet_addEthereumChain',
          params: [
            {
              'chainId': '0x${chainId.toRadixString(16)}',
              'chainName': chainName,
              'rpcUrls': [rpcUrl],
              'nativeCurrency': {
                'name': symbol,
                'symbol': symbol,
                'decimals': decimals,
              },
              if (explorerUrl != null) 'blockExplorerUrls': [explorerUrl],
            }
          ],
        ),
      );
    } catch (e) {
      AppLogger.e('Error adding chain', e);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Unsubscribe from session events
    _appKit?.onSessionConnect.unsubscribe(_onSessionConnect);
    _appKit?.onSessionDelete.unsubscribe(_onSessionDelete);
    _appKit?.onSessionEvent.unsubscribe(_onSessionEvent);
    _appKit?.onSessionUpdate.unsubscribe(_onSessionUpdate);

    // Unsubscribe from relay events
    _appKit?.core.relayClient.onRelayClientConnect.unsubscribe(_onRelayConnect);
    _appKit?.core.relayClient.onRelayClientDisconnect.unsubscribe(_onRelayDisconnect);
    _appKit?.core.relayClient.onRelayClientError.unsubscribe(_onRelayError);

    await _connectionController.close();
    await _accountsChangedController.close();
  }
}
