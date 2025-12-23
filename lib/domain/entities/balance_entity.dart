import 'package:equatable/equatable.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';

/// Native token balance (ETH, MATIC, BNB, SOL, etc.)
class NativeBalanceEntity extends Equatable {
  const NativeBalanceEntity({
    required this.address,
    required this.chain,
    required this.balanceWei,
    required this.balanceFormatted,
    required this.fetchedAt,
    this.error,
  });

  final String address;
  final ChainInfo chain;
  final BigInt balanceWei;
  final double balanceFormatted;
  final DateTime fetchedAt;
  final String? error;

  /// Check if balance has error
  bool get hasError => error != null;

  /// Check if balance data is stale (older than 30 seconds)
  bool get isStale => DateTime.now().difference(fetchedAt).inSeconds > 30;

  /// Create a copy with updated values
  NativeBalanceEntity copyWith({
    String? address,
    ChainInfo? chain,
    BigInt? balanceWei,
    double? balanceFormatted,
    DateTime? fetchedAt,
    String? error,
  }) {
    return NativeBalanceEntity(
      address: address ?? this.address,
      chain: chain ?? this.chain,
      balanceWei: balanceWei ?? this.balanceWei,
      balanceFormatted: balanceFormatted ?? this.balanceFormatted,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        address,
        chain.identifier,
        balanceWei,
        fetchedAt,
      ];
}

/// Token info for ERC-20/SPL tokens
class TokenEntity extends Equatable {
  const TokenEntity({
    required this.contractAddress,
    required this.symbol,
    required this.name,
    required this.decimals,
    this.iconUrl,
    required this.chainType,
  });

  final String contractAddress;
  final String symbol;
  final String name;
  final int decimals;
  final String? iconUrl;
  final ChainType chainType;

  /// Create a copy with updated values
  TokenEntity copyWith({
    String? contractAddress,
    String? symbol,
    String? name,
    int? decimals,
    String? iconUrl,
    ChainType? chainType,
  }) {
    return TokenEntity(
      contractAddress: contractAddress ?? this.contractAddress,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      decimals: decimals ?? this.decimals,
      iconUrl: iconUrl ?? this.iconUrl,
      chainType: chainType ?? this.chainType,
    );
  }

  @override
  List<Object?> get props => [contractAddress, symbol, chainType];
}

/// Token balance with metadata
class TokenBalanceEntity extends Equatable {
  const TokenBalanceEntity({
    required this.token,
    required this.ownerAddress,
    required this.chain,
    required this.balanceRaw,
    required this.balanceFormatted,
    required this.fetchedAt,
    this.error,
  });

  final TokenEntity token;
  final String ownerAddress;
  final ChainInfo chain;
  final BigInt balanceRaw;
  final double balanceFormatted;
  final DateTime fetchedAt;
  final String? error;

  /// Check if balance has error
  bool get hasError => error != null;

  /// Check if balance data is stale
  bool get isStale => DateTime.now().difference(fetchedAt).inSeconds > 30;

  /// Create a copy with updated values
  TokenBalanceEntity copyWith({
    TokenEntity? token,
    String? ownerAddress,
    ChainInfo? chain,
    BigInt? balanceRaw,
    double? balanceFormatted,
    DateTime? fetchedAt,
    String? error,
  }) {
    return TokenBalanceEntity(
      token: token ?? this.token,
      ownerAddress: ownerAddress ?? this.ownerAddress,
      chain: chain ?? this.chain,
      balanceRaw: balanceRaw ?? this.balanceRaw,
      balanceFormatted: balanceFormatted ?? this.balanceFormatted,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [
        token,
        ownerAddress,
        chain.identifier,
        balanceRaw,
      ];
}

/// Aggregated balance for a wallet across chains
class AggregatedBalanceEntity extends Equatable {
  const AggregatedBalanceEntity({
    required this.address,
    required this.nativeBalances,
    required this.tokenBalances,
    required this.lastUpdated,
  });

  final String address;
  final List<NativeBalanceEntity> nativeBalances;
  final List<TokenBalanceEntity> tokenBalances;
  final DateTime lastUpdated;

  /// Get native balance for specific chain
  NativeBalanceEntity? getBalanceForChain(ChainInfo chain) {
    return nativeBalances
        .where((b) => b.chain.identifier == chain.identifier)
        .firstOrNull;
  }

  /// Get total formatted native balance across all chains
  double get totalNativeBalance =>
      nativeBalances.fold(0.0, (sum, b) => sum + b.balanceFormatted);

  /// Check if any balance has error
  bool get hasAnyError =>
      nativeBalances.any((b) => b.hasError) ||
      tokenBalances.any((b) => b.hasError);

  /// Create a copy with updated values
  AggregatedBalanceEntity copyWith({
    String? address,
    List<NativeBalanceEntity>? nativeBalances,
    List<TokenBalanceEntity>? tokenBalances,
    DateTime? lastUpdated,
  }) {
    return AggregatedBalanceEntity(
      address: address ?? this.address,
      nativeBalances: nativeBalances ?? this.nativeBalances,
      tokenBalances: tokenBalances ?? this.tokenBalances,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  List<Object?> get props => [
        address,
        nativeBalances,
        tokenBalances,
        lastUpdated,
      ];
}
