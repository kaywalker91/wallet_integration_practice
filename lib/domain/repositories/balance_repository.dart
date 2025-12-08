import 'package:dartz/dartz.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/errors/failures.dart';
import 'package:wallet_integration_practice/domain/entities/balance_entity.dart';

/// Abstract balance repository interface
abstract class BalanceRepository {
  /// Get native token balance for a single address on a specific chain
  Future<Either<Failure, NativeBalanceEntity>> getNativeBalance({
    required String address,
    required ChainInfo chain,
    bool forceRefresh = false,
  });

  /// Get native token balances for an address across multiple chains
  Future<Either<Failure, List<NativeBalanceEntity>>> getNativeBalances({
    required String address,
    required List<ChainInfo> chains,
    bool forceRefresh = false,
  });

  /// Get ERC-20 token balance for a specific token
  Future<Either<Failure, TokenBalanceEntity>> getTokenBalance({
    required String address,
    required String tokenContract,
    required ChainInfo chain,
    bool forceRefresh = false,
  });

  /// Get multiple ERC-20 token balances for an address
  Future<Either<Failure, List<TokenBalanceEntity>>> getTokenBalances({
    required String address,
    required List<String> tokenContracts,
    required ChainInfo chain,
    bool forceRefresh = false,
  });

  /// Get aggregated balances (native + tokens) for a wallet
  Future<Either<Failure, AggregatedBalanceEntity>> getAggregatedBalances({
    required String address,
    required List<ChainInfo> chains,
    List<Map<ChainInfo, List<String>>>? tokensPerChain,
    bool forceRefresh = false,
  });

  /// Stream of balance updates for an address
  Stream<NativeBalanceEntity> watchBalance({
    required String address,
    required ChainInfo chain,
  });

  /// Clear balance cache for an address
  Future<void> clearCache({String? address, ChainInfo? chain});
}
