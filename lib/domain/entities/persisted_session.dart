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
    this.serializedSessionData,
    this.pairingTopic,
    this.peerName,
    this.peerIconUrl,
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

  /// Serialized SDK session data for re-injection (JSON string)
  final String? serializedSessionData;

  /// Pairing topic for session re-establishment
  final String? pairingTopic;

  /// Wallet peer name (from SDK metadata)
  final String? peerName;

  /// Wallet peer icon URL (from SDK metadata)
  final String? peerIconUrl;

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
    String? serializedSessionData,
    String? pairingTopic,
    String? peerName,
    String? peerIconUrl,
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
      serializedSessionData: serializedSessionData ?? this.serializedSessionData,
      pairingTopic: pairingTopic ?? this.pairingTopic,
      peerName: peerName ?? this.peerName,
      peerIconUrl: peerIconUrl ?? this.peerIconUrl,
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
        serializedSessionData,
        pairingTopic,
        peerName,
        peerIconUrl,
      ];
}
