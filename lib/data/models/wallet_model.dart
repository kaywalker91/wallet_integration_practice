import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';

/// Wallet data model for persistence
class WalletModel {
  final String address;
  final String walletType;
  final int? chainId;
  final String? cluster;
  final String? sessionTopic;
  final DateTime connectedAt;
  final Map<String, dynamic>? metadata;

  const WalletModel({
    required this.address,
    required this.walletType,
    this.chainId,
    this.cluster,
    this.sessionTopic,
    required this.connectedAt,
    this.metadata,
  });

  /// Create from JSON
  factory WalletModel.fromJson(Map<String, dynamic> json) {
    return WalletModel(
      address: json['address'] as String,
      walletType: json['walletType'] as String,
      chainId: json['chainId'] as int?,
      cluster: json['cluster'] as String?,
      sessionTopic: json['sessionTopic'] as String?,
      connectedAt: DateTime.parse(json['connectedAt'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'walletType': walletType,
      'chainId': chainId,
      'cluster': cluster,
      'sessionTopic': sessionTopic,
      'connectedAt': connectedAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Convert to entity
  WalletEntity toEntity() {
    return WalletEntity(
      address: address,
      type: _parseWalletType(walletType),
      chainId: chainId,
      cluster: cluster,
      sessionTopic: sessionTopic,
      connectedAt: connectedAt,
      metadata: metadata,
    );
  }

  /// Create from entity
  factory WalletModel.fromEntity(WalletEntity entity) {
    return WalletModel(
      address: entity.address,
      walletType: entity.type.name,
      chainId: entity.chainId,
      cluster: entity.cluster,
      sessionTopic: entity.sessionTopic,
      connectedAt: entity.connectedAt,
      metadata: entity.metadata,
    );
  }

  WalletType _parseWalletType(String type) {
    return WalletType.values.firstWhere(
      (e) => e.name == type,
      orElse: () => WalletType.walletConnect,
    );
  }
}
