import 'package:wallet_integration_practice/domain/entities/phantom_session.dart';

/// Phantom session data model for secure storage
///
/// Contains all data required to restore a Phantom wallet connection:
/// - X25519 key pair (dApp side)
/// - Phantom's public key
/// - Session token and wallet address
class PhantomSessionModel {
  const PhantomSessionModel({
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

  /// Create from JSON
  factory PhantomSessionModel.fromJson(Map<String, dynamic> json) {
    return PhantomSessionModel(
      dappPrivateKeyBase64: json['dappPrivateKeyBase64'] as String,
      dappPublicKeyBase64: json['dappPublicKeyBase64'] as String,
      phantomPublicKeyBase64: json['phantomPublicKeyBase64'] as String,
      session: json['session'] as String,
      connectedAddress: json['connectedAddress'] as String,
      cluster: json['cluster'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  /// Create from entity
  factory PhantomSessionModel.fromEntity(PhantomSession entity) {
    return PhantomSessionModel(
      dappPrivateKeyBase64: entity.dappPrivateKeyBase64,
      dappPublicKeyBase64: entity.dappPublicKeyBase64,
      phantomPublicKeyBase64: entity.phantomPublicKeyBase64,
      session: entity.session,
      connectedAddress: entity.connectedAddress,
      cluster: entity.cluster,
      createdAt: entity.createdAt,
      lastUsedAt: entity.lastUsedAt,
      expiresAt: entity.expiresAt,
    );
  }

  /// dApp's X25519 private key (Base64 encoded)
  final String dappPrivateKeyBase64;

  /// dApp's X25519 public key (Base64 encoded)
  final String dappPublicKeyBase64;

  /// Phantom's X25519 public key (Base64 encoded)
  final String phantomPublicKeyBase64;

  /// Session token from Phantom
  final String session;

  /// Connected wallet address
  final String connectedAddress;

  /// Solana cluster
  final String cluster;

  /// Session creation timestamp
  final DateTime createdAt;

  /// Last activity timestamp
  final DateTime lastUsedAt;

  /// Session expiration timestamp
  final DateTime? expiresAt;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'dappPrivateKeyBase64': dappPrivateKeyBase64,
      'dappPublicKeyBase64': dappPublicKeyBase64,
      'phantomPublicKeyBase64': phantomPublicKeyBase64,
      'session': session,
      'connectedAddress': connectedAddress,
      'cluster': cluster,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  /// Convert to entity
  PhantomSession toEntity() {
    return PhantomSession(
      dappPrivateKeyBase64: dappPrivateKeyBase64,
      dappPublicKeyBase64: dappPublicKeyBase64,
      phantomPublicKeyBase64: phantomPublicKeyBase64,
      session: session,
      connectedAddress: connectedAddress,
      cluster: cluster,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
    );
  }

  /// Create a copy with updated last used timestamp
  PhantomSessionModel copyWithLastUsed(DateTime lastUsedAt) {
    return PhantomSessionModel(
      dappPrivateKeyBase64: dappPrivateKeyBase64,
      dappPublicKeyBase64: dappPublicKeyBase64,
      phantomPublicKeyBase64: phantomPublicKeyBase64,
      session: session,
      connectedAddress: connectedAddress,
      cluster: cluster,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt,
      expiresAt: expiresAt,
    );
  }
}
