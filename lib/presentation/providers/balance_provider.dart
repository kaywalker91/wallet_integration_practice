import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_integration_practice/core/constants/app_constants.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/utils/address_validation_service.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';
import 'package:wallet_integration_practice/data/datasources/local/balance_cache_datasource.dart';
import 'package:wallet_integration_practice/data/datasources/remote/evm_balance_datasource.dart';
import 'package:wallet_integration_practice/data/datasources/remote/solana_balance_datasource.dart';
import 'package:wallet_integration_practice/data/repositories/balance_repository_impl.dart';
import 'package:wallet_integration_practice/domain/entities/balance_entity.dart';
import 'package:wallet_integration_practice/domain/repositories/balance_repository.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';

// ============================================================================
// Data Source Providers
// ============================================================================

/// Provider for SharedPreferences (needs to be overridden at app startup)
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be initialized before use');
});

/// Provider for EVM balance data source
final evmBalanceDataSourceProvider = Provider<EvmBalanceDataSource>((ref) {
  final dataSource = EvmBalanceDataSourceImpl();
  ref.onDispose(() => dataSource.dispose());
  return dataSource;
});

/// Provider for Solana balance data source
final solanaBalanceDataSourceProvider = Provider<SolanaBalanceDataSource>((ref) {
  final dataSource = SolanaBalanceDataSourceImpl();
  ref.onDispose(() => dataSource.dispose());
  return dataSource;
});

/// Provider for balance cache data source
final balanceCacheDataSourceProvider = Provider<BalanceCacheDataSource>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return BalanceCacheDataSourceImpl(prefs: prefs);
});

// ============================================================================
// Repository Provider
// ============================================================================

/// Provider for balance repository
final balanceRepositoryProvider = Provider<BalanceRepository>((ref) {
  final evmDataSource = ref.watch(evmBalanceDataSourceProvider);
  final solanaDataSource = ref.watch(solanaBalanceDataSourceProvider);
  final cacheDataSource = ref.watch(balanceCacheDataSourceProvider);

  final repository = BalanceRepositoryImpl(
    evmDataSource: evmDataSource,
    solanaDataSource: solanaDataSource,
    cacheDataSource: cacheDataSource,
  );

  ref.onDispose(() => repository.dispose());
  return repository;
});

// ============================================================================
// Balance State Providers
// ============================================================================

/// Provider for fetching native balance for a specific chain
/// Returns AsyncValue for loading/error states
final chainBalanceProvider =
    FutureProvider.family<NativeBalanceEntity?, ChainInfo>((ref, chain) async {
  final address = ref.watch(transactionAddressProvider);
  AppLogger.d('[DEBUG] chainBalanceProvider called - chain: ${chain.name}, address: $address');

  if (address == null) {
    AppLogger.w('[DEBUG] chainBalanceProvider: address is null, returning null');
    return null;
  }

  // === Defense in depth: Early validation at provider level ===
  // This prevents unnecessary repository calls when address format is wrong
  if (AppConstants.enableAddressValidation) {
    final validation = AddressValidationService.validateForChain(
      address: address,
      chainType: chain.type,
    );

    if (!validation.isValid) {
      final error = validation.error!;
      final detectedType = error.detectedChainType?.name ?? 'unknown';
      AppLogger.e(
        '[DEBUG] chainBalanceProvider: Address format mismatch - '
        'expected ${chain.type.name}, detected $detectedType',
      );

      // Return error entity without calling RPC
      return NativeBalanceEntity(
        address: address,
        chain: chain,
        balanceWei: BigInt.zero,
        balanceFormatted: 0.0,
        fetchedAt: DateTime.now(),
        error: 'Address format mismatch: expected ${chain.type.name} format',
      );
    }
  }

  final repository = ref.watch(balanceRepositoryProvider);
  AppLogger.d('[DEBUG] chainBalanceProvider: calling repository.getNativeBalance');

  final result = await repository.getNativeBalance(
    address: address,
    chain: chain,
  );

  return result.fold(
    (failure) {
      AppLogger.e('[DEBUG] chainBalanceProvider: FAILED - ${failure.message}');
      return NativeBalanceEntity(
        address: address,
        chain: chain,
        balanceWei: BigInt.zero,
        balanceFormatted: 0.0,
        fetchedAt: DateTime.now(),
        error: failure.message,
      );
    },
    (balance) {
      AppLogger.d('[DEBUG] chainBalanceProvider: SUCCESS - balanceWei: ${balance.balanceWei}, formatted: ${balance.balanceFormatted}');
      return balance;
    },
  );
});

/// Provider for current connected chain's balance
final currentChainBalanceProvider = FutureProvider<NativeBalanceEntity?>((ref) async {
  final activeEntry = ref.watch(activeWalletEntryProvider);
  final wallet = activeEntry?.wallet;
  AppLogger.d('[DEBUG] currentChainBalanceProvider called - wallet: ${wallet?.address}');

  if (wallet == null) {
    // Return null silently if no wallet is active - this is normal state
    return null;
  }

  AppLogger.d('[DEBUG] currentChainBalanceProvider: wallet.chainId=${wallet.chainId}, wallet.cluster=${wallet.cluster}');

  // Determine current chain
  ChainInfo? currentChain;
  if (wallet.chainId != null) {
    currentChain = SupportedChains.getByChainId(wallet.chainId!);
    AppLogger.d('[DEBUG] currentChainBalanceProvider: found EVM chain by chainId: ${currentChain?.name}');
  } else if (wallet.cluster != null) {
    // Solana
    currentChain = SupportedChains.solanaChains
        .where((c) => c.cluster == wallet.cluster)
        .firstOrNull;
    AppLogger.d('[DEBUG] currentChainBalanceProvider: found Solana chain by cluster: ${currentChain?.name}');
  }

  if (currentChain == null) {
    AppLogger.w('[DEBUG] currentChainBalanceProvider: currentChain is null - cannot determine chain');
    return null;
  }

  AppLogger.d('[DEBUG] currentChainBalanceProvider: fetching balance for chain: ${currentChain.name}');
  return ref.watch(chainBalanceProvider(currentChain).future);
});

/// Provider for fetching balances across multiple chains
final multiChainBalancesProvider =
    FutureProvider.family<List<NativeBalanceEntity>, List<ChainInfo>>(
        (ref, chains) async {
  final address = ref.watch(transactionAddressProvider);
  if (address == null) return [];

  final repository = ref.watch(balanceRepositoryProvider);
  final result = await repository.getNativeBalances(
    address: address,
    chains: chains,
  );

  return result.fold(
    (failure) {
      AppLogger.w('Failed to get multi-chain balances: ${failure.message}');
      return [];
    },
    (balances) => balances,
  );
});

/// Provider for all supported EVM chain balances
final allEvmBalancesProvider = FutureProvider<List<NativeBalanceEntity>>((ref) async {
  return ref.watch(multiChainBalancesProvider(SupportedChains.evmChains).future);
});

/// Provider for all supported Solana chain balances
final allSolanaBalancesProvider = FutureProvider<List<NativeBalanceEntity>>((ref) async {
  return ref.watch(multiChainBalancesProvider(SupportedChains.solanaChains).future);
});

/// Provider for all chain balances
final allBalancesProvider = FutureProvider<List<NativeBalanceEntity>>((ref) async {
  return ref.watch(multiChainBalancesProvider(SupportedChains.all).future);
});

// ============================================================================
// Token Balance Providers
// ============================================================================

/// Provider for single token balance
final tokenBalanceProvider = FutureProvider.family<TokenBalanceEntity?,
    ({String tokenContract, ChainInfo chain})>((ref, params) async {
  final address = ref.watch(transactionAddressProvider);
  if (address == null) return null;

  final repository = ref.watch(balanceRepositoryProvider);
  final result = await repository.getTokenBalance(
    address: address,
    tokenContract: params.tokenContract,
    chain: params.chain,
  );

  return result.fold(
    (failure) {
      AppLogger.w('Failed to get token balance: ${failure.message}');
      return null;
    },
    (balance) => balance,
  );
});

/// Provider for multiple token balances on a chain
final tokenBalancesProvider = FutureProvider.family<List<TokenBalanceEntity>,
    ({List<String> tokenContracts, ChainInfo chain})>((ref, params) async {
  final address = ref.watch(transactionAddressProvider);
  if (address == null) return [];

  final repository = ref.watch(balanceRepositoryProvider);
  final result = await repository.getTokenBalances(
    address: address,
    tokenContracts: params.tokenContracts,
    chain: params.chain,
  );

  return result.fold(
    (failure) {
      AppLogger.w('Failed to get token balances: ${failure.message}');
      return [];
    },
    (balances) => balances,
  );
});

// ============================================================================
// Aggregated Balance Provider
// ============================================================================

/// Provider for aggregated balances across chains
final aggregatedBalancesProvider = FutureProvider<AggregatedBalanceEntity?>((ref) async {
  final address = ref.watch(transactionAddressProvider);
  if (address == null) return null;

  final repository = ref.watch(balanceRepositoryProvider);
  final result = await repository.getAggregatedBalances(
    address: address,
    chains: SupportedChains.all,
  );

  return result.fold(
    (failure) {
      AppLogger.w('Failed to get aggregated balances: ${failure.message}');
      return AggregatedBalanceEntity(
        address: address,
        nativeBalances: const [],
        tokenBalances: const [],
        lastUpdated: DateTime.now(),
      );
    },
    (aggregated) => aggregated,
  );
});

// ============================================================================
// Balance Notifier (Manual Control)
// ============================================================================

/// State for balance management
class BalanceState {
  const BalanceState({
    this.isLoading = false,
    this.error,
    this.currentBalance,
    this.allBalances = const [],
    this.lastRefreshed,
  });

  final bool isLoading;
  final String? error;
  final NativeBalanceEntity? currentBalance;
  final List<NativeBalanceEntity> allBalances;
  final DateTime? lastRefreshed;

  BalanceState copyWith({
    bool? isLoading,
    String? error,
    NativeBalanceEntity? currentBalance,
    List<NativeBalanceEntity>? allBalances,
    DateTime? lastRefreshed,
  }) {
    return BalanceState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentBalance: currentBalance ?? this.currentBalance,
      allBalances: allBalances ?? this.allBalances,
      lastRefreshed: lastRefreshed ?? this.lastRefreshed,
    );
  }

  bool get hasError => error != null;
  bool get hasBalance => currentBalance != null;
}

/// Notifier for manual balance management
class BalanceNotifier extends Notifier<BalanceState> {
  @override
  BalanceState build() {
    return const BalanceState();
  }

  /// Refresh current chain balance
  Future<void> refreshCurrentBalance() async {
    final wallet = ref.read(connectedWalletProvider);
    if (wallet == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      // Determine current chain
      ChainInfo? currentChain;
      if (wallet.chainId != null) {
        currentChain = SupportedChains.getByChainId(wallet.chainId!);
      } else if (wallet.cluster != null) {
        currentChain = SupportedChains.solanaChains
            .where((c) => c.cluster == wallet.cluster)
            .firstOrNull;
      }

      if (currentChain == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Unknown chain',
        );
        return;
      }

      final repository = ref.read(balanceRepositoryProvider);
      final result = await repository.getNativeBalance(
        address: wallet.address,
        chain: currentChain,
        forceRefresh: true,
      );

      result.fold(
        (failure) {
          state = state.copyWith(
            isLoading: false,
            error: failure.message,
          );
        },
        (balance) {
          state = state.copyWith(
            isLoading: false,
            currentBalance: balance,
            lastRefreshed: DateTime.now(),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Refresh all chain balances
  Future<void> refreshAllBalances() async {
    final address = ref.read(transactionAddressProvider);
    if (address == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final repository = ref.read(balanceRepositoryProvider);
      final result = await repository.getNativeBalances(
        address: address,
        chains: SupportedChains.all,
        forceRefresh: true,
      );

      result.fold(
        (failure) {
          state = state.copyWith(
            isLoading: false,
            error: failure.message,
          );
        },
        (balances) {
          state = state.copyWith(
            isLoading: false,
            allBalances: balances,
            lastRefreshed: DateTime.now(),
          );
        },
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Clear cached balances
  Future<void> clearCache() async {
    final repository = ref.read(balanceRepositoryProvider);
    await repository.clearCache();
    state = const BalanceState();
    AppLogger.d('Balance cache cleared');
  }
}

/// Provider for balance notifier
final balanceNotifierProvider = NotifierProvider<BalanceNotifier, BalanceState>(
  BalanceNotifier.new,
);

// ============================================================================
// Balance Watch Stream Provider
// ============================================================================

/// Provider for watching balance updates on a specific chain
final balanceWatchProvider =
    StreamProvider.family<NativeBalanceEntity, ChainInfo>((ref, chain) {
  final address = ref.watch(transactionAddressProvider);
  if (address == null) {
    return const Stream.empty();
  }

  final repository = ref.watch(balanceRepositoryProvider);
  return repository.watchBalance(
    address: address,
    chain: chain,
  );
});

// ============================================================================
// Helper Providers
// ============================================================================

/// Provider for formatted balance string
final formattedBalanceProvider = Provider.family<String, NativeBalanceEntity?>((ref, balance) {
  if (balance == null) return '0.00';

  final formatted = balance.balanceFormatted;
  final symbol = balance.chain.symbol;

  // Format to reasonable decimal places
  if (formatted == 0) {
    return '0 $symbol';
  } else if (formatted < 0.0001) {
    return '<0.0001 $symbol';
  } else if (formatted < 1) {
    return '${formatted.toStringAsFixed(6)} $symbol';
  } else if (formatted < 1000) {
    return '${formatted.toStringAsFixed(4)} $symbol';
  } else {
    return '${formatted.toStringAsFixed(2)} $symbol';
  }
});

/// Provider for checking if balance is stale
final isBalanceStaleProvider = Provider.family<bool, NativeBalanceEntity?>((ref, balance) {
  if (balance == null) return true;
  return balance.isStale;
});

/// Provider for balance loading state
final isBalanceLoadingProvider = Provider<bool>((ref) {
  final currentBalance = ref.watch(currentChainBalanceProvider);
  return currentBalance.isLoading;
});

/// Provider for balance error state
final balanceErrorProvider = Provider<String?>((ref) {
  final currentBalance = ref.watch(currentChainBalanceProvider);
  return currentBalance.error?.toString();
});
