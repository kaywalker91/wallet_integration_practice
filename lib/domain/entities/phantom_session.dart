import 'package:equatable/equatable.dart';

/// Phantom session entity for restoring Solana wallet connections after app restart
///
/// Unlike WalletConnect-based sessions, Phantom uses X25519 key pairs for encryption.
/// To restore a session, we need to persist the dApp's key pair and Phantom's public key.
///
/// IMPORTANT: After restoring this session, connect() should NOT be called.
/// The restored keys allow direct signing operations (signMessage, signTransaction).
class PhantomSession extends Equatable {
  const PhantomSession({
    required this.dappPrivateKeyBase64,
    required this.dappPublicKeyBase64,
    required this.phantomPublicKeyBase64,
    required this.session,
    required this.connectedAddress,
    required this.cluster,
    required this.createdAt,
    required this.lastUsedAt,
    this.expiresAt,
  });

  /// dApp's X25519 private key (Base64 encoded)
  /// Used to decrypt responses from Phantom
  final String dappPrivateKeyBase64;

  /// dApp's X25519 public key (Base64 encoded)
  /// Sent to Phantom for encryption
  final String dappPublicKeyBase64;

  /// Phantom's X25519 public key (Base64 encoded)
  /// Received during initial connection, used for encryption
  final String phantomPublicKeyBase64;

  /// Session token from Phantom
  /// Identifies this dApp to Phantom
  final String session;

  /// Connected wallet address (Solana public key as Base58 string)
  final String connectedAddress;

  /// Solana cluster (mainnet-beta, devnet, testnet)
  final String cluster;

  /// Session creation timestamp
  final DateTime createdAt;

  /// Last activity timestamp
  final DateTime lastUsedAt;

  /// Session expiration timestamp
  final DateTime? expiresAt;

  /// Session validity duration (7 days, recommended by Phantom)
  static const Duration defaultSessionDuration = Duration(days: 7);

  /// Check if session is expired
  bool get isExpired {
    final expiry = expiresAt ?? createdAt.add(defaultSessionDuration);
    return DateTime.now().isAfter(expiry);
  }

  /// Check if session has all required keys for restoration
  bool get isValid {
    return dappPrivateKeyBase64.isNotEmpty &&
        dappPublicKeyBase64.isNotEmpty &&
        phantomPublicKeyBase64.isNotEmpty &&
        connectedAddress.isNotEmpty;
  }

  /// Create a copy with updated values
  PhantomSession copyWith({
    String? dappPrivateKeyBase64,
    String? dappPublicKeyBase64,
    String? phantomPublicKeyBase64,
    String? session,
    String? connectedAddress,
    String? cluster,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    DateTime? expiresAt,
  }) {
    return PhantomSession(
      dappPrivateKeyBase64: dappPrivateKeyBase64 ?? this.dappPrivateKeyBase64,
      dappPublicKeyBase64: dappPublicKeyBase64 ?? this.dappPublicKeyBase64,
      phantomPublicKeyBase64:
          phantomPublicKeyBase64 ?? this.phantomPublicKeyBase64,
      session: session ?? this.session,
      connectedAddress: connectedAddress ?? this.connectedAddress,
      cluster: cluster ?? this.cluster,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  /// Update last used timestamp
  PhantomSession markAsUsed() {
    return copyWith(lastUsedAt: DateTime.now());
  }

  @override
  List<Object?> get props => [
        dappPrivateKeyBase64,
        dappPublicKeyBase64,
        phantomPublicKeyBase64,
        session,
        connectedAddress,
        cluster,
        createdAt,
        lastUsedAt,
        expiresAt,
      ];
}
