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
    );
  }
}
