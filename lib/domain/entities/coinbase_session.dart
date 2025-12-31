import 'package:equatable/equatable.dart';

/// Coinbase Native SDK session entity
///
/// Unlike WalletConnect sessions, Coinbase SDK doesn't provide session topics.
/// This entity stores the minimum data needed to restore wallet state:
/// - Wallet address
/// - Chain ID
/// - Timestamps for session management
///
/// Coinbase SDK is stateless (Request-Response), so we only need to restore
/// the connected state - no actual reconnection is required.
class CoinbaseSession extends Equatable {
  const CoinbaseSession({
    required this.address,
    required this.chainId,
    required this.createdAt,
    required this.lastUsedAt,
    this.expiresAt,
  });

  /// Connected wallet address (EVM format: 0x...)
  final String address;

  /// Current chain ID (e.g., 1 for Ethereum mainnet)
  final int chainId;

  /// Session creation timestamp
  final DateTime createdAt;

  /// Last activity timestamp
  final DateTime lastUsedAt;

  /// Session expiration timestamp (optional, defaults to 30 days)
  final DateTime? expiresAt;

  /// Check if session is expired
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  /// Create a copy with updated last used timestamp
  CoinbaseSession markAsUsed() {
    return CoinbaseSession(
      address: address,
      chainId: chainId,
      createdAt: createdAt,
      lastUsedAt: DateTime.now(),
      expiresAt: expiresAt,
    );
  }

  /// Create a copy with updated chain ID
  CoinbaseSession copyWithChainId(int newChainId) {
    return CoinbaseSession(
      address: address,
      chainId: newChainId,
      createdAt: createdAt,
      lastUsedAt: DateTime.now(),
      expiresAt: expiresAt,
    );
  }

  @override
  List<Object?> get props => [
        address,
        chainId,
        createdAt,
        lastUsedAt,
        expiresAt,
      ];
}
