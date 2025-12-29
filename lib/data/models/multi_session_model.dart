import 'package:wallet_integration_practice/core/utils/logger.dart';
import 'package:wallet_integration_practice/data/models/persisted_session_model.dart';
import 'package:wallet_integration_practice/data/models/phantom_session_model.dart';
import 'package:wallet_integration_practice/domain/entities/multi_session_state.dart';
import 'package:wallet_integration_practice/domain/entities/persisted_session.dart';
import 'package:wallet_integration_practice/domain/entities/phantom_session.dart';

/// Multi-session entry data model for storage
class MultiSessionEntryModel {
  const MultiSessionEntryModel({
    required this.walletId,
    required this.sessionType,
    this.walletConnectSession,
    this.phantomSession,
    required this.createdAt,
    required this.lastUsedAt,
  });

  /// Create from JSON
  factory MultiSessionEntryModel.fromJson(Map<String, dynamic> json) {
    final sessionTypeStr = json['sessionType'] as String;
    final sessionType = SessionType.fromValue(sessionTypeStr);

    PersistedSessionModel? walletConnectSession;
    PhantomSessionModel? phantomSession;

    if (sessionType == SessionType.walletConnect &&
        json['walletConnectSession'] != null) {
      walletConnectSession = PersistedSessionModel.fromJson(
        json['walletConnectSession'] as Map<String, dynamic>,
      );
    }

    if (sessionType == SessionType.phantom && json['phantomSession'] != null) {
      phantomSession = PhantomSessionModel.fromJson(
        json['phantomSession'] as Map<String, dynamic>,
      );
    }

    return MultiSessionEntryModel(
      walletId: json['walletId'] as String,
      sessionType: sessionType,
      walletConnectSession: walletConnectSession,
      phantomSession: phantomSession,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
    );
  }

  /// Create from entity
  factory MultiSessionEntryModel.fromEntity(MultiSessionEntry entity) {
    return MultiSessionEntryModel(
      walletId: entity.walletId,
      sessionType: entity.sessionType,
      walletConnectSession: entity.walletConnectSession != null
          ? PersistedSessionModel.fromEntity(entity.walletConnectSession!)
          : null,
      phantomSession: entity.phantomSession != null
          ? PhantomSessionModel.fromEntity(entity.phantomSession!)
          : null,
      createdAt: entity.createdAt,
      lastUsedAt: entity.lastUsedAt,
    );
  }

  /// Create for WalletConnect-based session
  factory MultiSessionEntryModel.fromWalletConnect({
    required String walletId,
    required PersistedSessionModel session,
  }) {
    return MultiSessionEntryModel(
      walletId: walletId,
      sessionType: SessionType.walletConnect,
      walletConnectSession: session,
      createdAt: session.createdAt,
      lastUsedAt: session.lastUsedAt,
    );
  }

  /// Create for Phantom session
  factory MultiSessionEntryModel.fromPhantom({
    required String walletId,
    required PhantomSessionModel session,
  }) {
    return MultiSessionEntryModel(
      walletId: walletId,
      sessionType: SessionType.phantom,
      phantomSession: session,
      createdAt: session.createdAt,
      lastUsedAt: session.lastUsedAt,
    );
  }

  final String walletId;
  final SessionType sessionType;
  final PersistedSessionModel? walletConnectSession;
  final PhantomSessionModel? phantomSession;
  final DateTime createdAt;
  final DateTime lastUsedAt;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'walletId': walletId,
      'sessionType': sessionType.value,
      if (walletConnectSession != null)
        'walletConnectSession': walletConnectSession!.toJson(),
      if (phantomSession != null) 'phantomSession': phantomSession!.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
    };
  }

  /// Convert to entity
  MultiSessionEntry toEntity() {
    return MultiSessionEntry(
      walletId: walletId,
      sessionType: sessionType,
      walletConnectSession: walletConnectSession?.toEntity(),
      phantomSession: phantomSession?.toEntity(),
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
    );
  }

  /// Get the underlying PersistedSession entity
  PersistedSession? get persistedSessionEntity => walletConnectSession?.toEntity();

  /// Get the underlying PhantomSession entity
  PhantomSession? get phantomSessionEntity => phantomSession?.toEntity();

  /// Create a copy with updated last used timestamp
  MultiSessionEntryModel copyWithLastUsed(DateTime lastUsedAt) {
    return MultiSessionEntryModel(
      walletId: walletId,
      sessionType: sessionType,
      walletConnectSession: walletConnectSession,
      phantomSession: phantomSession?.copyWithLastUsed(lastUsedAt),
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
    );
  }
}

/// Multi-session state data model for storage
class MultiSessionStateModel {
  const MultiSessionStateModel({
    this.sessions = const {},
    this.activeWalletId,
    this.version = currentVersion,
  });

  /// Create from JSON
  factory MultiSessionStateModel.fromJson(Map<String, dynamic> json) {
    final sessionsJson = json['sessions'] as Map<String, dynamic>? ?? {};
    final sessions = <String, MultiSessionEntryModel>{};

    for (final entry in sessionsJson.entries) {
      try {
        sessions[entry.key] = MultiSessionEntryModel.fromJson(
          entry.value as Map<String, dynamic>,
        );
      } catch (e) {
        // Skip corrupted entries, log error
        AppLogger.w('Failed to parse session entry ${entry.key}: $e');
      }
    }

    return MultiSessionStateModel(
      sessions: sessions,
      activeWalletId: json['activeWalletId'] as String?,
      version: json['version'] as int? ?? 1,
    );
  }

  /// Create from entity
  factory MultiSessionStateModel.fromEntity(MultiSessionState entity) {
    final sessions = <String, MultiSessionEntryModel>{};
    for (final entry in entity.sessions.entries) {
      sessions[entry.key] = MultiSessionEntryModel.fromEntity(entry.value);
    }
    return MultiSessionStateModel(
      sessions: sessions,
      activeWalletId: entity.activeWalletId,
    );
  }

  /// Empty state factory
  factory MultiSessionStateModel.empty() => const MultiSessionStateModel();

  /// Current storage version for migration support
  static const int currentVersion = 1;

  final Map<String, MultiSessionEntryModel> sessions;
  final String? activeWalletId;
  final int version;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    final sessionsJson = <String, dynamic>{};
    for (final entry in sessions.entries) {
      sessionsJson[entry.key] = entry.value.toJson();
    }

    return {
      'sessions': sessionsJson,
      'activeWalletId': activeWalletId,
      'version': version,
    };
  }

  /// Convert to entity
  MultiSessionState toEntity() {
    final entitySessions = <String, MultiSessionEntry>{};
    for (final entry in sessions.entries) {
      entitySessions[entry.key] = entry.value.toEntity();
    }
    return MultiSessionState(
      sessions: entitySessions,
      activeWalletId: activeWalletId,
    );
  }

  /// Check if any session exists
  bool get isEmpty => sessions.isEmpty;

  /// Check if any session exists
  bool get isNotEmpty => sessions.isNotEmpty;

  /// Number of sessions
  int get count => sessions.length;

  /// Add or update a session
  MultiSessionStateModel addSession(MultiSessionEntryModel entry) {
    final updatedSessions = Map<String, MultiSessionEntryModel>.from(sessions);
    updatedSessions[entry.walletId] = entry;
    return MultiSessionStateModel(
      sessions: updatedSessions,
      activeWalletId: activeWalletId,
    );
  }

  /// Remove a session by walletId
  MultiSessionStateModel removeSession(String walletId) {
    final updatedSessions = Map<String, MultiSessionEntryModel>.from(sessions);
    updatedSessions.remove(walletId);
    return MultiSessionStateModel(
      sessions: updatedSessions,
      activeWalletId: activeWalletId == walletId ? null : activeWalletId,
    );
  }

  /// Set active wallet
  MultiSessionStateModel setActiveWallet(String? walletId) {
    return MultiSessionStateModel(
      sessions: sessions,
      activeWalletId: walletId,
    );
  }

  /// Clear all sessions
  MultiSessionStateModel clear() {
    return const MultiSessionStateModel();
  }

  /// Get all sessions as list
  List<MultiSessionEntryModel> get sessionList => sessions.values.toList();

  /// Get session by walletId
  MultiSessionEntryModel? getSession(String walletId) => sessions[walletId];
}
