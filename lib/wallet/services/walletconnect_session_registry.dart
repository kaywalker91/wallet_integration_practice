import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';
import 'package:wallet_integration_practice/domain/entities/persisted_session.dart';

/// Session lifecycle states for multi-session management
enum SessionState {
  /// Currently active and in use
  active,

  /// Valid session but not currently active
  inactive,

  /// Could not validate with SDK, may still be valid
  stale,

  /// Past expiration date, should be cleaned up
  expired,
}

/// Managed session wrapper for multi-wallet support
class ManagedSession {
  const ManagedSession({
    required this.topic,
    required this.walletId,
    required this.walletType,
    required this.address,
    required this.state,
    this.chainId,
    this.cluster,
    this.connectedAt,
    this.lastValidatedAt,
    this.expiresAt,
    this.serializedSessionData,
    this.pairingTopic,
    this.peerName,
    this.peerIconUrl,
  });

  /// Create from PersistedSession
  factory ManagedSession.fromPersistedSession(
    PersistedSession session, {
    required String walletId,
    required SessionState state,
  }) {
    return ManagedSession(
      topic: session.sessionTopic,
      walletId: walletId,
      walletType: _parseWalletType(session.walletType),
      address: session.address,
      state: state,
      chainId: session.chainId,
      cluster: session.cluster,
      connectedAt: session.createdAt,
      lastValidatedAt: session.lastUsedAt,
      expiresAt: session.expiresAt,
      serializedSessionData: session.serializedSessionData,
      pairingTopic: session.pairingTopic,
      peerName: session.peerName,
      peerIconUrl: session.peerIconUrl,
    );
  }

  /// Parse wallet type string to WalletType enum
  static WalletType _parseWalletType(String typeName) {
    final normalized = typeName.toLowerCase();
    return switch (normalized) {
      'metamask' => WalletType.metamask,
      'trustwallet' || 'trust' => WalletType.trustWallet,
      'okxwallet' || 'okx' => WalletType.okxWallet,
      'coinbase' || 'coinbasewallet' => WalletType.coinbase,
      'phantom' => WalletType.phantom,
      'rainbow' => WalletType.rainbow,
      'rabby' => WalletType.rabby,
      _ => WalletType.walletConnect,
    };
  }

  final String topic;
  final String walletId;
  final WalletType walletType;
  final String address;
  final SessionState state;
  final int? chainId;
  final String? cluster;
  final DateTime? connectedAt;
  final DateTime? lastValidatedAt;
  final DateTime? expiresAt;
  final String? serializedSessionData;
  final String? pairingTopic;
  final String? peerName;
  final String? peerIconUrl;

  /// Check if session is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Check if session has serialized data for re-injection
  bool get hasSerializedData => serializedSessionData != null;

  /// Create copy with updated state
  ManagedSession copyWithState(SessionState newState) {
    return ManagedSession(
      topic: topic,
      walletId: walletId,
      walletType: walletType,
      address: address,
      state: newState,
      chainId: chainId,
      cluster: cluster,
      connectedAt: connectedAt,
      lastValidatedAt: DateTime.now(),
      expiresAt: expiresAt,
      serializedSessionData: serializedSessionData,
      pairingTopic: pairingTopic,
      peerName: peerName,
      peerIconUrl: peerIconUrl,
    );
  }

  /// Convert to PersistedSession entity
  PersistedSession toPersistedSession() {
    return PersistedSession(
      walletType: walletType.name,
      sessionTopic: topic,
      address: address,
      chainId: chainId,
      cluster: cluster,
      createdAt: connectedAt ?? DateTime.now(),
      lastUsedAt: lastValidatedAt ?? DateTime.now(),
      expiresAt: expiresAt,
      serializedSessionData: serializedSessionData,
      pairingTopic: pairingTopic,
      peerName: peerName,
      peerIconUrl: peerIconUrl,
    );
  }

  @override
  String toString() {
    return 'ManagedSession('
        'topic: ${topic.substring(0, 8)}..., '
        'wallet: ${walletType.name}, '
        'state: $state, '
        'address: ${address.substring(0, 10)}...)';
  }
}

/// Session validation result
class SessionValidationResult {
  const SessionValidationResult({
    required this.isValid,
    required this.state,
    this.message,
  });

  factory SessionValidationResult.valid() {
    return const SessionValidationResult(
      isValid: true,
      state: SessionState.active,
    );
  }

  factory SessionValidationResult.stale(String message) {
    return SessionValidationResult(
      isValid: false,
      state: SessionState.stale,
      message: message,
    );
  }

  factory SessionValidationResult.expired(String message) {
    return SessionValidationResult(
      isValid: false,
      state: SessionState.expired,
      message: message,
    );
  }

  final bool isValid;
  final SessionState state;
  final String? message;
}

/// WalletConnect Session Registry Service
///
/// Manages multiple WalletConnect sessions across different wallets,
/// providing session state tracking, validation, and lifecycle management.
///
/// Key responsibilities:
/// - Track multiple sessions from different wallets
/// - Manage session states (active, inactive, stale, expired)
/// - Validate sessions against SDK state
/// - Cleanup expired sessions
/// - Support session switching without re-connection
class WalletConnectSessionRegistry {
  WalletConnectSessionRegistry();

  /// In-memory session cache
  final Map<String, ManagedSession> _sessions = {};

  /// Currently active session topic
  String? _activeSessionTopic;

  /// Get active session topic
  String? get activeSessionTopic => _activeSessionTopic;

  /// Get active session
  ManagedSession? get activeSession {
    if (_activeSessionTopic == null) return null;
    return _sessions[_activeSessionTopic];
  }

  /// Register a new session
  void registerSession(ManagedSession session) {
    _sessions[session.topic] = session;
    AppLogger.wallet('Session registered in registry', data: {
      'topic': session.topic.substring(0, 8),
      'walletType': session.walletType.name,
      'state': session.state.name,
    });
  }

  /// Set active session by topic
  bool setActiveSession(String topic) {
    if (!_sessions.containsKey(topic)) {
      AppLogger.wallet('Cannot activate session - not found', data: {
        'topic': topic.length > 8 ? '${topic.substring(0, 8)}...' : topic,
      });
      return false;
    }

    // Mark previous active session as inactive
    if (_activeSessionTopic != null && _sessions.containsKey(_activeSessionTopic)) {
      final previousSession = _sessions[_activeSessionTopic]!;
      _sessions[_activeSessionTopic!] = previousSession.copyWithState(SessionState.inactive);
    }

    // Mark new session as active
    final session = _sessions[topic]!;
    _sessions[topic] = session.copyWithState(SessionState.active);
    _activeSessionTopic = topic;

    AppLogger.wallet('Session activated', data: {
      'topic': topic.substring(0, 8),
      'walletType': session.walletType.name,
    });
    return true;
  }

  /// Get session by topic
  ManagedSession? getSession(String topic) => _sessions[topic];

  /// Get session by wallet ID
  ManagedSession? getSessionByWalletId(String walletId) {
    return _sessions.values.where((s) => s.walletId == walletId).firstOrNull;
  }

  /// Get all sessions
  List<ManagedSession> getAllSessions() => _sessions.values.toList();

  /// Get sessions by state
  List<ManagedSession> getSessionsByState(SessionState state) {
    return _sessions.values.where((s) => s.state == state).toList();
  }

  /// Get sessions by wallet type
  List<ManagedSession> getSessionsByWalletType(WalletType type) {
    return _sessions.values.where((s) => s.walletType == type).toList();
  }

  /// Update session state
  void updateSessionState(String topic, SessionState state) {
    final session = _sessions[topic];
    if (session == null) return;

    _sessions[topic] = session.copyWithState(state);
    AppLogger.wallet('Session state updated', data: {
      'topic': topic.substring(0, 8),
      'newState': state.name,
    });
  }

  /// Validate session against SDK topics
  SessionValidationResult validateSession(String topic, Set<String> sdkTopics) {
    final session = _sessions[topic];
    if (session == null) {
      return SessionValidationResult.stale('Session not found in registry');
    }

    // Check expiration
    if (session.isExpired) {
      updateSessionState(topic, SessionState.expired);
      return SessionValidationResult.expired('Session has expired');
    }

    // Check if in SDK
    if (sdkTopics.contains(topic)) {
      updateSessionState(topic, SessionState.active);
      return SessionValidationResult.valid();
    }

    // Not in SDK but not expired - mark as stale
    updateSessionState(topic, SessionState.stale);
    return SessionValidationResult.stale('Session not found in SDK');
  }

  /// Remove session by topic
  void removeSession(String topic) {
    if (_sessions.remove(topic) != null) {
      AppLogger.wallet('Session removed from registry', data: {
        'topic': topic.length > 8 ? '${topic.substring(0, 8)}...' : topic,
      });
      if (_activeSessionTopic == topic) {
        _activeSessionTopic = null;
      }
    }
  }

  /// Cleanup expired sessions
  int cleanupExpiredSessions() {
    final expiredTopics = _sessions.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();

    for (final topic in expiredTopics) {
      removeSession(topic);
    }

    if (expiredTopics.isNotEmpty) {
      AppLogger.wallet('Expired sessions cleaned up', data: {
        'count': expiredTopics.length,
      });
    }

    return expiredTopics.length;
  }

  /// Mark sessions not in SDK as stale
  void markStaleSessionsFromSdk(Set<String> sdkTopics) {
    for (final entry in _sessions.entries) {
      if (!sdkTopics.contains(entry.key) && entry.value.state != SessionState.expired) {
        updateSessionState(entry.key, SessionState.stale);
      }
    }
  }

  /// Mark a specific session as stale by walletId
  /// Returns true if session was found and marked, false otherwise
  bool markSessionStaleByWalletId(String walletId) {
    final session = getSessionByWalletId(walletId);
    if (session == null) {
      AppLogger.wallet('Cannot mark session stale - walletId not found', data: {
        'walletId': walletId,
      });
      return false;
    }

    updateSessionState(session.topic, SessionState.stale);
    AppLogger.wallet('Session marked as stale by walletId', data: {
      'walletId': walletId,
      'topic': session.topic.substring(0, 8),
      'walletType': session.walletType.name,
    });
    return true;
  }

  /// Get all stale sessions for UI display
  List<ManagedSession> getStaleSessions() {
    return getSessionsByState(SessionState.stale);
  }

  /// Check if a session is stale by topic
  bool isSessionStale(String topic) {
    final session = _sessions[topic];
    return session?.state == SessionState.stale;
  }

  /// Check if a session is stale by walletId
  bool isSessionStaleByWalletId(String walletId) {
    final session = getSessionByWalletId(walletId);
    return session?.state == SessionState.stale;
  }

  /// Get session count
  int get sessionCount => _sessions.length;

  /// Check if any session exists
  bool get isEmpty => _sessions.isEmpty;

  /// Check if any session exists
  bool get isNotEmpty => _sessions.isNotEmpty;

  /// Clear all sessions
  void clear() {
    _sessions.clear();
    _activeSessionTopic = null;
    AppLogger.wallet('Session registry cleared');
  }

  /// Get summary for logging
  Map<String, dynamic> getSummary() {
    final byState = <SessionState, int>{};
    for (final session in _sessions.values) {
      byState[session.state] = (byState[session.state] ?? 0) + 1;
    }

    return {
      'totalSessions': sessionCount,
      'activeSessionTopic': _activeSessionTopic?.substring(0, 8),
      'byState': byState.map((k, v) => MapEntry(k.name, v)),
    };
  }
}
