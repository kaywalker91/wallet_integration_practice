import 'package:wallet_integration_practice/domain/entities/persisted_session.dart';

/// Persisted session data model for storage
class PersistedSessionModel {
  const PersistedSessionModel({
    required this.walletType,
    required this.sessionTopic,
    required this.address,
    this.chainId,
    this.cluster,
    required this.createdAt,
    required this.lastUsedAt,
    this.expiresAt,
    this.serializedSessionData,
    this.pairingTopic,
    this.peerName,
    this.peerIconUrl,
  });

  /// Create from JSON
  factory PersistedSessionModel.fromJson(Map<String, dynamic> json) {
    return PersistedSessionModel(
      walletType: json['walletType'] as String,
      sessionTopic: json['sessionTopic'] as String,
      address: json['address'] as String,
      chainId: json['chainId'] as int?,
      cluster: json['cluster'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      serializedSessionData: json['serializedSessionData'] as String?,
      pairingTopic: json['pairingTopic'] as String?,
      peerName: json['peerName'] as String?,
      peerIconUrl: json['peerIconUrl'] as String?,
    );
  }

  /// Create from entity
  factory PersistedSessionModel.fromEntity(PersistedSession entity) {
    return PersistedSessionModel(
      walletType: entity.walletType,
      sessionTopic: entity.sessionTopic,
      address: entity.address,
      chainId: entity.chainId,
      cluster: entity.cluster,
      createdAt: entity.createdAt,
      lastUsedAt: entity.lastUsedAt,
      expiresAt: entity.expiresAt,
      serializedSessionData: entity.serializedSessionData,
      pairingTopic: entity.pairingTopic,
      peerName: entity.peerName,
      peerIconUrl: entity.peerIconUrl,
    );
  }

  final String walletType;
  final String sessionTopic;
  final String address;
  final int? chainId;
  final String? cluster;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final DateTime? expiresAt;

  /// Serialized SDK session data for re-injection (JSON string)
  final String? serializedSessionData;

  /// Pairing topic for session re-establishment
  final String? pairingTopic;

  /// Wallet peer name (from SDK metadata)
  final String? peerName;

  /// Wallet peer icon URL (from SDK metadata)
  final String? peerIconUrl;

  /// Check if session is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'walletType': walletType,
      'sessionTopic': sessionTopic,
      'address': address,
      'chainId': chainId,
      'cluster': cluster,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
      'serializedSessionData': serializedSessionData,
      'pairingTopic': pairingTopic,
      'peerName': peerName,
      'peerIconUrl': peerIconUrl,
    };
  }

  /// Convert to entity
  PersistedSession toEntity() {
    return PersistedSession(
      walletType: walletType,
      sessionTopic: sessionTopic,
      address: address,
      chainId: chainId,
      cluster: cluster,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
      serializedSessionData: serializedSessionData,
      pairingTopic: pairingTopic,
      peerName: peerName,
      peerIconUrl: peerIconUrl,
    );
  }

  /// Create a copy with updated last used timestamp
  PersistedSessionModel copyWithLastUsed(DateTime lastUsedAt) {
    return PersistedSessionModel(
      walletType: walletType,
      sessionTopic: sessionTopic,
      address: address,
      chainId: chainId,
      cluster: cluster,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
      serializedSessionData: serializedSessionData,
      pairingTopic: pairingTopic,
      peerName: peerName,
      peerIconUrl: peerIconUrl,
    );
  }
}
