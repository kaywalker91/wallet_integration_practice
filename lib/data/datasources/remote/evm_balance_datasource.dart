import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';

/// Token info returned from contract
class TokenInfo {
  const TokenInfo({
    required this.symbol,
    required this.name,
    required this.decimals,
  });

  final String symbol;
  final String name;
  final int decimals;
}

/// Remote data source for EVM chain balance queries
abstract class EvmBalanceDataSource {
  /// Get native token balance (ETH, MATIC, BNB, etc.)
  Future<BigInt> getNativeBalance(String address, ChainInfo chain);

  /// Get ERC-20 token balance
  Future<BigInt> getTokenBalance(
    String address,
    String tokenContract,
    ChainInfo chain,
  );

  /// Get ERC-20 token info (symbol, name, decimals)
  Future<TokenInfo> getTokenInfo(String tokenContract, ChainInfo chain);

  /// Get multiple token balances in a batch call
  Future<Map<String, BigInt>> getMultipleTokenBalances(
    String address,
    List<String> tokenContracts,
    ChainInfo chain,
  );

  /// Dispose resources
  void dispose();
}

/// Implementation using web3dart
class EvmBalanceDataSourceImpl implements EvmBalanceDataSource {
  /// Cache Web3Client instances per chain for connection reuse
  final Map<String, Web3Client> _clientCache = {};

  Web3Client _getClient(ChainInfo chain) {
    final key = chain.identifier;
    if (!_clientCache.containsKey(key)) {
      _clientCache[key] = Web3Client(chain.rpcUrl, http.Client());
    }
    return _clientCache[key]!;
  }

  @override
  Future<BigInt> getNativeBalance(String address, ChainInfo chain) async {
    AppLogger.d('[DEBUG] EvmDataSource.getNativeBalance called - address: $address, chain: ${chain.name}, rpcUrl: ${chain.rpcUrl}');

    try {
      final client = _getClient(chain);
      AppLogger.d('[DEBUG] EvmDataSource: Got Web3Client');

      final ethAddress = EthereumAddress.fromHex(address);
      AppLogger.d('[DEBUG] EvmDataSource: Parsed address: ${ethAddress.hex}');

      AppLogger.d('[DEBUG] EvmDataSource: Calling client.getBalance...');
      final balance = await client.getBalance(ethAddress);
      AppLogger.d('[DEBUG] EvmDataSource: RPC returned balance: ${balance.getInWei} wei');

      return balance.getInWei;
    } catch (e, stackTrace) {
      AppLogger.e('[DEBUG] EvmDataSource: EXCEPTION - $e', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch native balance from ${chain.name}',
        originalException: e,
      );
    }
  }

  @override
  Future<BigInt> getTokenBalance(
    String address,
    String tokenContract,
    ChainInfo chain,
  ) async {
    try {
      final client = _getClient(chain);
      final contract = DeployedContract(
        ContractAbi.fromJson(_erc20BalanceOfAbi, 'ERC20'),
        EthereumAddress.fromHex(tokenContract),
      );
      final balanceOf = contract.function('balanceOf');

      final result = await client.call(
        contract: contract,
        function: balanceOf,
        params: [EthereumAddress.fromHex(address)],
      );

      final balance = result.first as BigInt;
      AppLogger.d(
        'Fetched token balance for $address on ${chain.name}: $balance',
      );
      return balance;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get token balance', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch token balance from ${chain.name}',
        originalException: e,
      );
    }
  }

  @override
  Future<TokenInfo> getTokenInfo(String tokenContract, ChainInfo chain) async {
    try {
      final client = _getClient(chain);
      final contract = DeployedContract(
        ContractAbi.fromJson(_erc20MetadataAbi, 'ERC20'),
        EthereumAddress.fromHex(tokenContract),
      );

      final symbolFn = contract.function('symbol');
      final nameFn = contract.function('name');
      final decimalsFn = contract.function('decimals');

      final results = await Future.wait([
        client.call(contract: contract, function: symbolFn, params: []),
        client.call(contract: contract, function: nameFn, params: []),
        client.call(contract: contract, function: decimalsFn, params: []),
      ]);

      final tokenInfo = TokenInfo(
        symbol: results[0].first as String,
        name: results[1].first as String,
        decimals: (results[2].first as BigInt).toInt(),
      );

      AppLogger.d(
        'Fetched token info for $tokenContract: ${tokenInfo.symbol}',
      );
      return tokenInfo;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get token info', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch token info from ${chain.name}',
        originalException: e,
      );
    }
  }

  @override
  Future<Map<String, BigInt>> getMultipleTokenBalances(
    String address,
    List<String> tokenContracts,
    ChainInfo chain,
  ) async {
    // Execute balance queries in parallel
    final results = await Future.wait(
      tokenContracts.map(
        (contract) => getTokenBalance(address, contract, chain).catchError(
          (_) => BigInt.zero,
        ),
      ),
    );

    return Map.fromIterables(tokenContracts, results);
  }

  @override
  void dispose() {
    for (final client in _clientCache.values) {
      client.dispose();
    }
    _clientCache.clear();
  }

  // Minimal ERC20 ABI for balance queries
  static const String _erc20BalanceOfAbi = '''[
    {
      "constant": true,
      "inputs": [{"name": "owner", "type": "address"}],
      "name": "balanceOf",
      "outputs": [{"name": "", "type": "uint256"}],
      "type": "function"
    }
  ]''';

  static const String _erc20MetadataAbi = '''[
    {
      "constant": true,
      "inputs": [],
      "name": "symbol",
      "outputs": [{"name": "", "type": "string"}],
      "type": "function"
    },
    {
      "constant": true,
      "inputs": [],
      "name": "name",
      "outputs": [{"name": "", "type": "string"}],
      "type": "function"
    },
    {
      "constant": true,
      "inputs": [],
      "name": "decimals",
      "outputs": [{"name": "", "type": "uint8"}],
      "type": "function"
    }
  ]''';
}
