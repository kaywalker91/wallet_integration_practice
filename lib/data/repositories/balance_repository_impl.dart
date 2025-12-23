import 'dart:async';
import 'package:dartz/dartz.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/core/errors/failures.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';
import 'package:wallet_integration_practice/data/datasources/local/balance_cache_datasource.dart';
import 'package:wallet_integration_practice/data/datasources/remote/evm_balance_datasource.dart';
import 'package:wallet_integration_practice/data/datasources/remote/solana_balance_datasource.dart';
import 'package:wallet_integration_practice/data/models/balance_model.dart';
import 'package:wallet_integration_practice/domain/entities/balance_entity.dart';
import 'package:wallet_integration_practice/domain/repositories/balance_repository.dart';

/// Implementation of BalanceRepository
class BalanceRepositoryImpl implements BalanceRepository {
  BalanceRepositoryImpl({
    required EvmBalanceDataSource evmDataSource,
    required SolanaBalanceDataSource solanaDataSource,
    required BalanceCacheDataSource cacheDataSource,
  })  : _evmDataSource = evmDataSource,
        _solanaDataSource = solanaDataSource,
        _cacheDataSource = cacheDataSource;

  final EvmBalanceDataSource _evmDataSource;
  final SolanaBalanceDataSource _solanaDataSource;
  final BalanceCacheDataSource _cacheDataSource;

  /// Stream controllers for balance watching
  final Map<String, StreamController<NativeBalanceEntity>> _watchControllers = {};

  @override
  Future<Either<Failure, NativeBalanceEntity>> getNativeBalance({
    required String address,
    required ChainInfo chain,
    bool forceRefresh = false,
  }) async {
    AppLogger.d('[DEBUG] Repository.getNativeBalance called - address: $address, chain: ${chain.name}, rpcUrl: ${chain.rpcUrl}');

    try {
      // Check cache first (if not forcing refresh)
      if (!forceRefresh) {
        final cached = await _cacheDataSource.getCachedNativeBalance(
          address: address,
          chainIdentifier: chain.identifier,
        );
        if (cached != null) {
          AppLogger.d('[DEBUG] Repository: Returning cached balance for $address on ${chain.name}');
          return Right(cached.toEntity(chain));
        }
        AppLogger.d('[DEBUG] Repository: No cache found, fetching from RPC');
      } else {
        AppLogger.d('[DEBUG] Repository: forceRefresh=true, skipping cache');
      }

      // Fetch from appropriate data source
      final BigInt balanceWei;
      AppLogger.d('[DEBUG] Repository: chain.type = ${chain.type}');

      if (chain.type == ChainType.evm) {
        AppLogger.d('[DEBUG] Repository: Calling EVM datasource...');
        balanceWei = await _evmDataSource.getNativeBalance(address, chain);
        AppLogger.d('[DEBUG] Repository: EVM datasource returned: $balanceWei');
      } else if (chain.type == ChainType.solana) {
        AppLogger.d('[DEBUG] Repository: Calling Solana datasource...');
        balanceWei = await _solanaDataSource.getNativeBalance(address, chain);
        AppLogger.d('[DEBUG] Repository: Solana datasource returned: $balanceWei');
      } else {
        AppLogger.e('[DEBUG] Repository: Unsupported chain type: ${chain.type}');
        return Left(BalanceFailure.unsupportedChain(chain.chainId, chain.cluster));
      }

      // Create entity
      final entity = NativeBalanceEntity(
        address: address,
        chain: chain,
        balanceWei: balanceWei,
        balanceFormatted: _formatBalance(balanceWei, chain),
        fetchedAt: DateTime.now(),
      );

      // Cache the result
      await _cacheDataSource.cacheNativeBalance(
        NativeBalanceModel.fromEntity(entity),
      );
      AppLogger.d('[DEBUG] Repository: Balance cached successfully');

      // Notify watchers
      _notifyWatchers(entity);

      AppLogger.d('[DEBUG] Repository: Returning success - balanceWei: ${entity.balanceWei}, formatted: ${entity.balanceFormatted}');
      return Right(entity);
    } on BalanceException catch (e) {
      AppLogger.e('[DEBUG] Repository: BalanceException caught - ${e.message}', e.originalException);
      return Left(BalanceFailure.rpcError(chain.name, e.originalException));
    } catch (e) {
      AppLogger.e('[DEBUG] Repository: Unknown exception caught', e);
      return Left(BalanceFailure.unknown(e));
    }
  }

  @override
  Future<Either<Failure, List<NativeBalanceEntity>>> getNativeBalances({
    required String address,
    required List<ChainInfo> chains,
    bool forceRefresh = false,
  }) async {
    try {
      final results = await Future.wait(
        chains.map((chain) => getNativeBalance(
              address: address,
              chain: chain,
              forceRefresh: forceRefresh,
            )),
      );

      final balances = <NativeBalanceEntity>[];
      for (final result in results) {
        result.fold(
          (failure) => AppLogger.w('Failed to get balance: ${failure.message}'),
          (balance) => balances.add(balance),
        );
      }

      return Right(balances);
    } catch (e) {
      return Left(BalanceFailure.unknown(e));
    }
  }

  @override
  Future<Either<Failure, TokenBalanceEntity>> getTokenBalance({
    required String address,
    required String tokenContract,
    required ChainInfo chain,
    bool forceRefresh = false,
  }) async {
    try {
      // Only EVM chains support ERC-20 tokens in this implementation
      if (chain.type != ChainType.evm) {
        return Left(BalanceFailure.unsupportedChain(chain.chainId, chain.cluster));
      }

      // Check cache first
      if (!forceRefresh) {
        final cached = await _cacheDataSource.getCachedTokenBalance(
          address: address,
          tokenContract: tokenContract,
          chainIdentifier: chain.identifier,
        );
        if (cached != null) {
          return Right(cached.toEntity(chain));
        }
      }

      // Fetch token balance
      final balanceRaw = await _evmDataSource.getTokenBalance(
        address,
        tokenContract,
        chain,
      );

      // Fetch token info
      final tokenInfo = await _evmDataSource.getTokenInfo(tokenContract, chain);

      // Create token entity
      final token = TokenEntity(
        contractAddress: tokenContract,
        symbol: tokenInfo.symbol,
        name: tokenInfo.name,
        decimals: tokenInfo.decimals,
        chainType: chain.type,
      );

      // Create balance entity
      final entity = TokenBalanceEntity(
        token: token,
        ownerAddress: address,
        chain: chain,
        balanceRaw: balanceRaw,
        balanceFormatted: _formatTokenBalance(balanceRaw, tokenInfo.decimals),
        fetchedAt: DateTime.now(),
      );

      // Cache the result
      await _cacheDataSource.cacheTokenBalance(
        TokenBalanceModel.fromEntity(entity),
      );

      return Right(entity);
    } on BalanceException catch (e) {
      return Left(BalanceFailure.rpcError(chain.name, e.originalException));
    } catch (e) {
      return Left(BalanceFailure.unknown(e));
    }
  }

  @override
  Future<Either<Failure, List<TokenBalanceEntity>>> getTokenBalances({
    required String address,
    required List<String> tokenContracts,
    required ChainInfo chain,
    bool forceRefresh = false,
  }) async {
    try {
      final results = await Future.wait(
        tokenContracts.map((contract) => getTokenBalance(
              address: address,
              tokenContract: contract,
              chain: chain,
              forceRefresh: forceRefresh,
            )),
      );

      final balances = <TokenBalanceEntity>[];
      for (final result in results) {
        result.fold(
          (failure) => AppLogger.w('Failed to get token balance: ${failure.message}'),
          (balance) => balances.add(balance),
        );
      }

      return Right(balances);
    } catch (e) {
      return Left(BalanceFailure.unknown(e));
    }
  }

  @override
  Future<Either<Failure, AggregatedBalanceEntity>> getAggregatedBalances({
    required String address,
    required List<ChainInfo> chains,
    List<Map<ChainInfo, List<String>>>? tokensPerChain,
    bool forceRefresh = false,
  }) async {
    try {
      // Get native balances for all chains
      final nativeResult = await getNativeBalances(
        address: address,
        chains: chains,
        forceRefresh: forceRefresh,
      );

      final nativeBalances = nativeResult.fold(
        (failure) => <NativeBalanceEntity>[],
        (balances) => balances,
      );

      // Get token balances if specified
      final tokenBalances = <TokenBalanceEntity>[];
      if (tokensPerChain != null) {
        for (final chainTokens in tokensPerChain) {
          for (final entry in chainTokens.entries) {
            final chain = entry.key;
            final contracts = entry.value;

            final tokenResult = await getTokenBalances(
              address: address,
              tokenContracts: contracts,
              chain: chain,
              forceRefresh: forceRefresh,
            );

            tokenResult.fold(
              (failure) => AppLogger.w('Failed to get tokens: ${failure.message}'),
              (balances) => tokenBalances.addAll(balances),
            );
          }
        }
      }

      return Right(AggregatedBalanceEntity(
        address: address,
        nativeBalances: nativeBalances,
        tokenBalances: tokenBalances,
        lastUpdated: DateTime.now(),
      ));
    } catch (e) {
      return Left(BalanceFailure.unknown(e));
    }
  }

  @override
  Stream<NativeBalanceEntity> watchBalance({
    required String address,
    required ChainInfo chain,
  }) {
    final key = '${address}_${chain.identifier}';

    if (!_watchControllers.containsKey(key)) {
      _watchControllers[key] = StreamController<NativeBalanceEntity>.broadcast(
        onCancel: () {
          _watchControllers[key]?.close();
          _watchControllers.remove(key);
        },
      );

      // Initial fetch
      getNativeBalance(address: address, chain: chain).then((result) {
        result.fold(
          (failure) => AppLogger.w('Watch initial fetch failed: ${failure.message}'),
          (balance) => _watchControllers[key]?.add(balance),
        );
      });
    }

    return _watchControllers[key]!.stream;
  }

  @override
  Future<void> clearCache({String? address, ChainInfo? chain}) async {
    await _cacheDataSource.clearCache(
      address: address,
      chainIdentifier: chain?.identifier,
    );
  }

  /// Format native balance from wei to human-readable
  double _formatBalance(BigInt balanceWei, ChainInfo chain) {
    // Native tokens typically use 18 decimals for EVM, 9 for Solana
    final decimals = chain.type == ChainType.solana ? 9 : 18;
    return balanceWei / BigInt.from(10).pow(decimals);
  }

  /// Format token balance to human-readable
  double _formatTokenBalance(BigInt balanceRaw, int decimals) {
    return balanceRaw / BigInt.from(10).pow(decimals);
  }

  /// Notify watchers of balance update
  void _notifyWatchers(NativeBalanceEntity balance) {
    final key = '${balance.address}_${balance.chain.identifier}';
    _watchControllers[key]?.add(balance);
  }

  /// Dispose resources
  void dispose() {
    for (final controller in _watchControllers.values) {
      controller.close();
    }
    _watchControllers.clear();

    final evmDs = _evmDataSource;
    if (evmDs is EvmBalanceDataSourceImpl) {
      evmDs.dispose();
    }
    final solanaDs = _solanaDataSource;
    if (solanaDs is SolanaBalanceDataSourceImpl) {
      solanaDs.dispose();
    }
  }
}
