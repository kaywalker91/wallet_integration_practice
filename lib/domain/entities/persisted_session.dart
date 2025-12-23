import 'package:equatable/equatable.dart';

/// Persisted session entity for restoring wallet connections after app restart
class PersistedSession extends Equatable {
  const PersistedSession({
    required this.walletType,
    required this.sessionTopic,
    required this.address,
    this.chainId,
    this.cluster,
    required this.createdAt,
    required this.lastUsedAt,
    this.expiresAt,
  });

  /// Wallet type name (e.g., 'walletConnect', 'metaMask', 'phantom')
  final String walletType;

  /// WalletConnect session topic (unique identifier)
  final String sessionTopic;

  /// Connected wallet address
  final String address;

  /// EVM chain ID (for EVM wallets)
  final int? chainId;

  /// Solana cluster (for Solana wallets)
  final String? cluster;

  /// Session creation timestamp
  final DateTime createdAt;

  /// Last activity timestamp
  final DateTime lastUsedAt;

  /// Session expiration timestamp
  final DateTime? expiresAt;

  /// Session validity duration (7 days)
  static const Duration defaultSessionDuration = Duration(days: 7);

  /// Check if session is expired
  bool get isExpired {
    final expiry = expiresAt ?? createdAt.add(defaultSessionDuration);
    return DateTime.now().isAfter(expiry);
  }

  /// Check if this is an EVM session
  bool get isEvmSession => chainId != null;

  /// Check if this is a Solana session
  bool get isSolanaSession => cluster != null;

  /// Check if this is a WalletConnect-based session
  bool get isWalletConnectBased {
    final type = walletType.toLowerCase();
    return type == 'walletconnect' ||
        type == 'metamask' ||
        type == 'trustwallet' ||
        type == 'okxwallet' ||
        type == 'rabby' ||
        type == 'coinbasewallet';
  }

  /// Create a copy with updated values
  PersistedSession copyWith({
    String? walletType,
    String? sessionTopic,
    String? address,
    int? chainId,
    String? cluster,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    DateTime? expiresAt,
  }) {
    return PersistedSession(
      walletType: walletType ?? this.walletType,
      sessionTopic: sessionTopic ?? this.sessionTopic,
      address: address ?? this.address,
      chainId: chainId ?? this.chainId,
      cluster: cluster ?? this.cluster,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Update last used timestamp
  PersistedSession markAsUsed() {
    return copyWith(lastUsedAt: DateTime.now());
  }

  @override
  List<Object?> get props => [
        walletType,
        sessionTopic,
        address,
        chainId,
        cluster,
        createdAt,
        lastUsedAt,
        expiresAt,
      ];
}
