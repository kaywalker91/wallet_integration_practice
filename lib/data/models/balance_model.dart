import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/domain/entities/balance_entity.dart';

/// Native balance data model for persistence/caching
class NativeBalanceModel {
  const NativeBalanceModel({
    required this.address,
    required this.chainIdentifier,
    required this.balanceWei,
    required this.balanceFormatted,
    required this.fetchedAt,
    this.error,
  });

  /// Create from JSON
  factory NativeBalanceModel.fromJson(Map<String, dynamic> json) {
    return NativeBalanceModel(
      address: json['address'] as String,
      chainIdentifier: json['chainIdentifier'] as String,
      balanceWei: json['balanceWei'] as String,
      balanceFormatted: (json['balanceFormatted'] as num).toDouble(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      error: json['error'] as String?,
    );
  }

  /// Create from entity
  factory NativeBalanceModel.fromEntity(NativeBalanceEntity entity) {
    return NativeBalanceModel(
      address: entity.address,
      chainIdentifier: entity.chain.identifier,
      balanceWei: entity.balanceWei.toString(),
      balanceFormatted: entity.balanceFormatted,
      fetchedAt: entity.fetchedAt,
      error: entity.error,
    );
  }

  final String address;
  final String chainIdentifier;
  final String balanceWei;
  final double balanceFormatted;
  final DateTime fetchedAt;
  final String? error;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'chainIdentifier': chainIdentifier,
      'balanceWei': balanceWei,
      'balanceFormatted': balanceFormatted,
      'fetchedAt': fetchedAt.toIso8601String(),
      'error': error,
    };
  }

  /// Convert to entity
  NativeBalanceEntity toEntity(ChainInfo chain) {
    return NativeBalanceEntity(
      address: address,
      chain: chain,
      balanceWei: BigInt.parse(balanceWei),
      balanceFormatted: balanceFormatted,
      fetchedAt: fetchedAt,
      error: error,
    );
  }
}

/// Token data model for persistence
class TokenModel {
  const TokenModel({
    required this.contractAddress,
    required this.symbol,
    required this.name,
    required this.decimals,
    this.iconUrl,
    required this.chainType,
  });

  /// Create from JSON
  factory TokenModel.fromJson(Map<String, dynamic> json) {
    return TokenModel(
      contractAddress: json['contractAddress'] as String,
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      decimals: json['decimals'] as int,
      iconUrl: json['iconUrl'] as String?,
      chainType: json['chainType'] as String,
    );
  }

  /// Create from entity
  factory TokenModel.fromEntity(TokenEntity entity) {
    return TokenModel(
      contractAddress: entity.contractAddress,
      symbol: entity.symbol,
      name: entity.name,
      decimals: entity.decimals,
      iconUrl: entity.iconUrl,
      chainType: entity.chainType.name,
    );
  }

  final String contractAddress;
  final String symbol;
  final String name;
  final int decimals;
  final String? iconUrl;
  final String chainType;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'contractAddress': contractAddress,
      'symbol': symbol,
      'name': name,
      'decimals': decimals,
      'iconUrl': iconUrl,
      'chainType': chainType,
    };
  }

  /// Convert to entity
  TokenEntity toEntity() {
    return TokenEntity(
      contractAddress: contractAddress,
      symbol: symbol,
      name: name,
      decimals: decimals,
      iconUrl: iconUrl,
      chainType: ChainType.values.firstWhere(
        (e) => e.name == chainType,
        orElse: () => ChainType.evm,
      ),
    );
  }
}

/// Token balance data model for persistence/caching
class TokenBalanceModel {
  const TokenBalanceModel({
    required this.token,
    required this.ownerAddress,
    required this.chainIdentifier,
    required this.balanceRaw,
    required this.balanceFormatted,
    required this.fetchedAt,
    this.error,
  });

  /// Create from JSON
  factory TokenBalanceModel.fromJson(Map<String, dynamic> json) {
    return TokenBalanceModel(
      token: TokenModel.fromJson(json['token'] as Map<String, dynamic>),
      ownerAddress: json['ownerAddress'] as String,
      chainIdentifier: json['chainIdentifier'] as String,
      balanceRaw: json['balanceRaw'] as String,
      balanceFormatted: (json['balanceFormatted'] as num).toDouble(),
      fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      error: json['error'] as String?,
    );
  }

  /// Create from entity
  factory TokenBalanceModel.fromEntity(TokenBalanceEntity entity) {
    return TokenBalanceModel(
      token: TokenModel.fromEntity(entity.token),
      ownerAddress: entity.ownerAddress,
      chainIdentifier: entity.chain.identifier,
      balanceRaw: entity.balanceRaw.toString(),
      balanceFormatted: entity.balanceFormatted,
      fetchedAt: entity.fetchedAt,
      error: entity.error,
    );
  }

  final TokenModel token;
  final String ownerAddress;
  final String chainIdentifier;
  final String balanceRaw;
  final double balanceFormatted;
  final DateTime fetchedAt;
  final String? error;

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'token': token.toJson(),
      'ownerAddress': ownerAddress,
      'chainIdentifier': chainIdentifier,
      'balanceRaw': balanceRaw,
      'balanceFormatted': balanceFormatted,
      'fetchedAt': fetchedAt.toIso8601String(),
      'error': error,
    };
  }

  /// Convert to entity
  TokenBalanceEntity toEntity(ChainInfo chain) {
    return TokenBalanceEntity(
      token: token.toEntity(),
      ownerAddress: ownerAddress,
      chain: chain,
      balanceRaw: BigInt.parse(balanceRaw),
      balanceFormatted: balanceFormatted,
      fetchedAt: fetchedAt,
      error: error,
    );
  }
}
