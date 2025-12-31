import 'package:wallet_integration_practice/domain/entities/coinbase_session.dart';

/// Coinbase session data model for secure storage
///
/// Simpler than WalletConnect or Phantom models because:
/// - No session topic (Coinbase uses Native SDK, not WalletConnect)
/// - No encryption keys (SDK handles auth internally)
/// - Stateless operation (only need address + chain for state restoration)
class CoinbaseSessionModel {
  const CoinbaseSessionModel({
    required this.address,
    required this.chainId,
    required this.createdAt,
    required this.lastUsedAt,
    this.expiresAt,
  });

  /// Create from JSON
  factory CoinbaseSessionModel.fromJson(Map<String, dynamic> json) {
    return CoinbaseSessionModel(
      address: json['address'] as String,
      chainId: json['chainId'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  /// Create from entity
  factory CoinbaseSessionModel.fromEntity(CoinbaseSession entity) {
    return CoinbaseSessionModel(
      address: entity.address,
      chainId: entity.chainId,
      createdAt: entity.createdAt,
      lastUsedAt: entity.lastUsedAt,
      expiresAt: entity.expiresAt,
    );
  }

  /// Connected wallet address (EVM format: 0x...)
  final String address;

  /// Current chain ID (e.g., 1 for Ethereum mainnet)
  final int chainId;

  /// Session creation timestamp
  final DateTime createdAt;

  /// Last activity timestamp
  final DateTime lastUsedAt;

  /// Session expiration timestamp
  final DateTime? expiresAt;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'chainId': chainId,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  /// Convert to entity
  CoinbaseSession toEntity() {
    return CoinbaseSession(
      address: address,
      chainId: chainId,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
    );
  }

  /// Check if session is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Create a copy with updated last used timestamp
  CoinbaseSessionModel copyWithLastUsed(DateTime lastUsedAt) {
    return CoinbaseSessionModel(
      address: address,
      chainId: chainId,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
    );
  }

  /// Create a copy with updated chain ID
  CoinbaseSessionModel copyWithChainId(int newChainId) {
    return CoinbaseSessionModel(
      address: address,
      chainId: newChainId,
      createdAt: createdAt,
      lastUsedAt: DateTime.now(),
      expiresAt: expiresAt,
    );
  }
}
