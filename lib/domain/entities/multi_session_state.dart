import 'package:equatable/equatable.dart';
import 'package:wallet_integration_practice/domain/entities/persisted_session.dart';
import 'package:wallet_integration_practice/domain/entities/phantom_session.dart';

/// Session type discriminator for storage
enum SessionType {
  walletConnect,
  phantom;

  String get value {
    switch (this) {
      case SessionType.walletConnect:
        return 'walletConnect';
      case SessionType.phantom:
        return 'phantom';
    }
  }

  static SessionType fromValue(String value) {
    switch (value) {
      case 'walletConnect':
        return SessionType.walletConnect;
      case 'phantom':
        return SessionType.phantom;
      default:
        throw ArgumentError('Unknown session type: $value');
    }
  }
}

/// Unified session entry that can hold either WalletConnect or Phantom session
class MultiSessionEntry extends Equatable {
  const MultiSessionEntry({
    required this.walletId,
    required this.sessionType,
    this.walletConnectSession,
    this.phantomSession,
    required this.createdAt,
    required this.lastUsedAt,
  }) : assert(
          (sessionType == SessionType.walletConnect &&
                  walletConnectSession != null) ||
              (sessionType == SessionType.phantom && phantomSession != null),
          'Session data must match session type',
        );

  /// Create entry for WalletConnect-based session
  factory MultiSessionEntry.fromWalletConnect({
    required String walletId,
    required PersistedSession session,
  }) {
    return MultiSessionEntry(
      walletId: walletId,
      sessionType: SessionType.walletConnect,
      walletConnectSession: session,
      createdAt: session.createdAt,
      lastUsedAt: session.lastUsedAt,
    );
  }

  /// Create entry for Phantom session
  factory MultiSessionEntry.fromPhantom({
    required String walletId,
    required PhantomSession session,
  }) {
    return MultiSessionEntry(
      walletId: walletId,
      sessionType: SessionType.phantom,
      phantomSession: session,
      createdAt: session.createdAt,
      lastUsedAt: session.lastUsedAt,
    );
  }

  /// Unique identifier for this wallet session
  /// Format: {walletType}_{address} (e.g., "metamask_0x123..." or "phantom_ABC...")
  final String walletId;

  /// Type of session (walletConnect or phantom)
  final SessionType sessionType;

  /// WalletConnect-based session data (if sessionType == walletConnect)
  final PersistedSession? walletConnectSession;

  /// Phantom session data (if sessionType == phantom)
  final PhantomSession? phantomSession;

  /// Session creation timestamp
  final DateTime createdAt;

  /// Last activity timestamp
  final DateTime lastUsedAt;

  /// Check if session is expired
  bool get isExpired {
    switch (sessionType) {
      case SessionType.walletConnect:
        return walletConnectSession?.isExpired ?? true;
      case SessionType.phantom:
        return phantomSession?.isExpired ?? true;
    }
  }

  /// Get connected address
  String get address {
    switch (sessionType) {
      case SessionType.walletConnect:
        return walletConnectSession?.address ?? '';
      case SessionType.phantom:
        return phantomSession?.connectedAddress ?? '';
    }
  }

  /// Get wallet type name
  String get walletType {
    switch (sessionType) {
      case SessionType.walletConnect:
        return walletConnectSession?.walletType ?? '';
      case SessionType.phantom:
        return 'phantom';
    }
  }

  /// Create a copy with updated last used timestamp
  MultiSessionEntry markAsUsed() {
    final now = DateTime.now();
    return MultiSessionEntry(
      walletId: walletId,
      sessionType: sessionType,
      walletConnectSession: walletConnectSession?.markAsUsed(),
      phantomSession: phantomSession?.markAsUsed(),
      createdAt: createdAt,
      lastUsedAt: now,
    );
  }

  @override
  List<Object?> get props => [
        walletId,
        sessionType,
        walletConnectSession,
        phantomSession,
        createdAt,
        lastUsedAt,
      ];
}

/// State container for multiple wallet sessions
class MultiSessionState extends Equatable {
  const MultiSessionState({
    this.sessions = const {},
    this.activeWalletId,
  });

  /// Empty state factory
  factory MultiSessionState.empty() => const MultiSessionState();

  /// Map of wallet sessions keyed by walletId
  final Map<String, MultiSessionEntry> sessions;

  /// Currently active wallet ID
  final String? activeWalletId;

  /// Get active session entry
  MultiSessionEntry? get activeSession {
    if (activeWalletId == null) return null;
    return sessions[activeWalletId];
  }

  /// Get all non-expired sessions
  List<MultiSessionEntry> get validSessions {
    return sessions.values.where((s) => !s.isExpired).toList();
  }

  /// Get all expired sessions
  List<MultiSessionEntry> get expiredSessions {
    return sessions.values.where((s) => s.isExpired).toList();
  }

  /// Check if any session exists
  bool get isEmpty => sessions.isEmpty;

  /// Check if any session exists
  bool get isNotEmpty => sessions.isNotEmpty;

  /// Number of sessions
  int get count => sessions.length;

  /// Add or update a session
  MultiSessionState addSession(MultiSessionEntry entry) {
    final updatedSessions = Map<String, MultiSessionEntry>.from(sessions);
    updatedSessions[entry.walletId] = entry;
    return MultiSessionState(
      sessions: updatedSessions,
      activeWalletId: activeWalletId,
    );
  }

  /// Remove a session by walletId
  MultiSessionState removeSession(String walletId) {
    final updatedSessions = Map<String, MultiSessionEntry>.from(sessions);
    updatedSessions.remove(walletId);
    return MultiSessionState(
      sessions: updatedSessions,
      activeWalletId: activeWalletId == walletId ? null : activeWalletId,
    );
  }

  /// Set active wallet
  MultiSessionState setActiveWallet(String? walletId) {
    return MultiSessionState(
      sessions: sessions,
      activeWalletId: walletId,
    );
  }

  /// Clear all sessions
  MultiSessionState clear() {
    return const MultiSessionState();
  }

  /// Remove all expired sessions
  MultiSessionState removeExpired() {
    final updatedSessions = Map<String, MultiSessionEntry>.from(sessions);
    updatedSessions.removeWhere((_, entry) => entry.isExpired);
    return MultiSessionState(
      sessions: updatedSessions,
      activeWalletId:
          updatedSessions.containsKey(activeWalletId) ? activeWalletId : null,
    );
  }

  @override
  List<Object?> get props => [sessions, activeWalletId];
}

/// Helper extension to generate wallet ID
extension WalletIdGenerator on String {
  /// Generate walletId from wallet type and address
  static String generate(String walletType, String address) {
    final normalizedType = walletType.toLowerCase().replaceAll(' ', '');
    final normalizedAddress = address.toLowerCase();
    return '${normalizedType}_$normalizedAddress';
  }
}
