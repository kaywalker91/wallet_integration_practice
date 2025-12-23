import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';
import 'package:wallet_integration_practice/data/models/balance_model.dart';

/// Local data source for balance caching with TTL support
abstract class BalanceCacheDataSource {
  /// Save native balance to cache
  Future<void> cacheNativeBalance(NativeBalanceModel balance);

  /// Get cached native balance
  Future<NativeBalanceModel?> getCachedNativeBalance({
    required String address,
    required String chainIdentifier,
  });

  /// Save token balance to cache
  Future<void> cacheTokenBalance(TokenBalanceModel balance);

  /// Get cached token balance
  Future<TokenBalanceModel?> getCachedTokenBalance({
    required String address,
    required String tokenContract,
    required String chainIdentifier,
  });

  /// Save multiple token balances to cache
  Future<void> cacheTokenBalances(List<TokenBalanceModel> balances);

  /// Get all cached token balances for an address on a chain
  Future<List<TokenBalanceModel>> getCachedTokenBalances({
    required String address,
    required String chainIdentifier,
  });

  /// Clear cache for specific address
  Future<void> clearCache({String? address, String? chainIdentifier});

  /// Clear all balance cache
  Future<void> clearAllCache();

  /// Check if cached data is valid (not expired)
  bool isCacheValid(DateTime fetchedAt, {Duration? ttl});
}

/// Implementation using SharedPreferences
class BalanceCacheDataSourceImpl implements BalanceCacheDataSource {
  BalanceCacheDataSourceImpl({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  /// Default cache TTL: 30 seconds
  static const Duration defaultTtl = Duration(seconds: 30);

  /// Cache key prefix
  static const String _cachePrefix = 'balance_cache_';
  static const String _nativePrefix = '${_cachePrefix}native_';
  static const String _tokenPrefix = '${_cachePrefix}token_';
  static const String _tokenListPrefix = '${_cachePrefix}token_list_';

  /// Generate cache key for native balance
  String _nativeKey(String address, String chainIdentifier) =>
      '$_nativePrefix${address}_$chainIdentifier';

  /// Generate cache key for token balance
  String _tokenKey(String address, String tokenContract, String chainIdentifier) =>
      '$_tokenPrefix${address}_${tokenContract}_$chainIdentifier';

  /// Generate cache key for token balance list
  String _tokenListKey(String address, String chainIdentifier) =>
      '$_tokenListPrefix${address}_$chainIdentifier';

  @override
  Future<void> cacheNativeBalance(NativeBalanceModel balance) async {
    try {
      final key = _nativeKey(balance.address, balance.chainIdentifier);
      final json = jsonEncode(balance.toJson());
      await _prefs.setString(key, json);
      AppLogger.d('Cached native balance for ${balance.address}');
    } catch (e) {
      throw StorageException(
        message: 'Failed to cache native balance',
        originalException: e,
      );
    }
  }

  @override
  Future<NativeBalanceModel?> getCachedNativeBalance({
    required String address,
    required String chainIdentifier,
  }) async {
    try {
      final key = _nativeKey(address, chainIdentifier);
      final json = _prefs.getString(key);
      if (json == null) return null;

      final model = NativeBalanceModel.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      // Check if cache is valid
      if (!isCacheValid(model.fetchedAt)) {
        AppLogger.d('Native balance cache expired for $address');
        return null;
      }

      AppLogger.d('Retrieved cached native balance for $address');
      return model;
    } catch (e) {
      AppLogger.e('Failed to get cached native balance', e);
      return null;
    }
  }

  @override
  Future<void> cacheTokenBalance(TokenBalanceModel balance) async {
    try {
      final key = _tokenKey(
        balance.ownerAddress,
        balance.token.contractAddress,
        balance.chainIdentifier,
      );
      final json = jsonEncode(balance.toJson());
      await _prefs.setString(key, json);
      AppLogger.d('Cached token balance for ${balance.token.symbol}');
    } catch (e) {
      throw StorageException(
        message: 'Failed to cache token balance',
        originalException: e,
      );
    }
  }

  @override
  Future<TokenBalanceModel?> getCachedTokenBalance({
    required String address,
    required String tokenContract,
    required String chainIdentifier,
  }) async {
    try {
      final key = _tokenKey(address, tokenContract, chainIdentifier);
      final json = _prefs.getString(key);
      if (json == null) return null;

      final model = TokenBalanceModel.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );

      // Check if cache is valid
      if (!isCacheValid(model.fetchedAt)) {
        AppLogger.d('Token balance cache expired for $tokenContract');
        return null;
      }

      AppLogger.d('Retrieved cached token balance for ${model.token.symbol}');
      return model;
    } catch (e) {
      AppLogger.e('Failed to get cached token balance', e);
      return null;
    }
  }

  @override
  Future<void> cacheTokenBalances(List<TokenBalanceModel> balances) async {
    if (balances.isEmpty) return;

    try {
      // Cache individual balances
      for (final balance in balances) {
        await cacheTokenBalance(balance);
      }

      // Also store the list of token contracts for this address/chain
      final first = balances.first;
      final listKey = _tokenListKey(first.ownerAddress, first.chainIdentifier);
      final contracts = balances.map((b) => b.token.contractAddress).toList();
      await _prefs.setStringList(listKey, contracts);

      AppLogger.d('Cached ${balances.length} token balances');
    } catch (e) {
      throw StorageException(
        message: 'Failed to cache token balances',
        originalException: e,
      );
    }
  }

  @override
  Future<List<TokenBalanceModel>> getCachedTokenBalances({
    required String address,
    required String chainIdentifier,
  }) async {
    try {
      final listKey = _tokenListKey(address, chainIdentifier);
      final contracts = _prefs.getStringList(listKey);
      if (contracts == null || contracts.isEmpty) return [];

      final balances = <TokenBalanceModel>[];
      for (final contract in contracts) {
        final balance = await getCachedTokenBalance(
          address: address,
          tokenContract: contract,
          chainIdentifier: chainIdentifier,
        );
        if (balance != null) {
          balances.add(balance);
        }
      }

      AppLogger.d('Retrieved ${balances.length} cached token balances');
      return balances;
    } catch (e) {
      AppLogger.e('Failed to get cached token balances', e);
      return [];
    }
  }

  @override
  Future<void> clearCache({String? address, String? chainIdentifier}) async {
    try {
      final keys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix));

      for (final key in keys) {
        bool shouldRemove = true;

        if (address != null && !key.contains(address)) {
          shouldRemove = false;
        }
        if (chainIdentifier != null && !key.contains(chainIdentifier)) {
          shouldRemove = false;
        }

        if (shouldRemove) {
          await _prefs.remove(key);
        }
      }

      AppLogger.d('Cleared balance cache${address != null ? ' for $address' : ''}');
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear balance cache',
        originalException: e,
      );
    }
  }

  @override
  Future<void> clearAllCache() async {
    try {
      final keys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
      for (final key in keys) {
        await _prefs.remove(key);
      }
      AppLogger.d('Cleared all balance cache');
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear all balance cache',
        originalException: e,
      );
    }
  }

  @override
  bool isCacheValid(DateTime fetchedAt, {Duration? ttl}) {
    final effectiveTtl = ttl ?? defaultTtl;
    final now = DateTime.now();
    return now.difference(fetchedAt) < effectiveTtl;
  }
}
