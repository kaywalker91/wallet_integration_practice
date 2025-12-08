import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';

/// SPL Token info returned from on-chain data
class SplTokenInfo {
  final String mint;
  final String symbol;
  final String name;
  final int decimals;

  const SplTokenInfo({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
  });
}

/// Remote data source for Solana chain balance queries
abstract class SolanaBalanceDataSource {
  /// Get native SOL balance
  Future<BigInt> getNativeBalance(String address, ChainInfo chain);

  /// Get SPL token balance
  Future<BigInt> getTokenBalance(
    String address,
    String mintAddress,
    ChainInfo chain,
  );

  /// Get all SPL token accounts for an address
  Future<List<SplTokenAccount>> getTokenAccounts(
    String address,
    ChainInfo chain,
  );

  /// Get SPL token info (symbol, name, decimals) from mint
  Future<SplTokenInfo> getTokenInfo(String mintAddress, ChainInfo chain);

  /// Dispose resources
  void dispose();
}

/// SPL Token account with balance
class SplTokenAccount {
  final String mint;
  final String tokenAccount;
  final BigInt balance;
  final int decimals;

  const SplTokenAccount({
    required this.mint,
    required this.tokenAccount,
    required this.balance,
    required this.decimals,
  });
}

/// Implementation using Solana JSON-RPC directly via HTTP
/// This approach avoids package API compatibility issues
class SolanaBalanceDataSourceImpl implements SolanaBalanceDataSource {
  /// HTTP client for RPC calls
  final http.Client _httpClient;

  /// Known token metadata cache
  final Map<String, SplTokenInfo> _tokenMetadataCache = {};

  SolanaBalanceDataSourceImpl({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Make a JSON-RPC call to Solana
  Future<dynamic> _rpcCall(
    String rpcUrl,
    String method,
    List<dynamic> params,
  ) async {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': params,
    });

    final response = await _httpClient.post(
      Uri.parse(rpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw BalanceException(
        message: 'RPC call failed with status ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json.containsKey('error')) {
      final error = json['error'];
      throw BalanceException(
        message: 'RPC error: ${error['message'] ?? error}',
      );
    }

    return json['result'];
  }

  @override
  Future<BigInt> getNativeBalance(String address, ChainInfo chain) async {
    AppLogger.d('[DEBUG] SolanaDataSource.getNativeBalance called - address: $address, chain: ${chain.name}, rpcUrl: ${chain.rpcUrl}');

    try {
      AppLogger.d('[DEBUG] SolanaDataSource: Calling RPC getBalance...');
      final result = await _rpcCall(
        chain.rpcUrl,
        'getBalance',
        [address],
      );

      AppLogger.d('[DEBUG] SolanaDataSource: RPC result: $result');
      final value = result['value'] as int;
      AppLogger.d('[DEBUG] SolanaDataSource: Balance value: $value lamports');

      return BigInt.from(value);
    } catch (e, stackTrace) {
      AppLogger.e('[DEBUG] SolanaDataSource: EXCEPTION - $e', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch SOL balance from ${chain.name}',
        originalException: e,
      );
    }
  }

  @override
  Future<BigInt> getTokenBalance(
    String address,
    String mintAddress,
    ChainInfo chain,
  ) async {
    try {
      // Get token accounts filtered by mint
      final result = await _rpcCall(
        chain.rpcUrl,
        'getTokenAccountsByOwner',
        [
          address,
          {'mint': mintAddress},
          {'encoding': 'jsonParsed'},
        ],
      );

      final accounts = result['value'] as List<dynamic>;
      BigInt totalBalance = BigInt.zero;

      for (final account in accounts) {
        final data = account['account']['data']['parsed']['info'];
        final amount = data['tokenAmount']['amount'] as String;
        totalBalance += BigInt.parse(amount);
      }

      AppLogger.d(
        'Fetched token balance for $address on ${chain.name}: $totalBalance',
      );
      return totalBalance;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get SPL token balance', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch SPL token balance from ${chain.name}',
        originalException: e,
      );
    }
  }

  @override
  Future<List<SplTokenAccount>> getTokenAccounts(
    String address,
    ChainInfo chain,
  ) async {
    try {
      // Token program ID
      const tokenProgramId = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';

      final result = await _rpcCall(
        chain.rpcUrl,
        'getTokenAccountsByOwner',
        [
          address,
          {'programId': tokenProgramId},
          {'encoding': 'jsonParsed'},
        ],
      );

      final accountsList = result['value'] as List<dynamic>;
      final accounts = <SplTokenAccount>[];

      for (final account in accountsList) {
        final pubkey = account['pubkey'] as String;
        final data = account['account']['data']['parsed']['info'];
        final mint = data['mint'] as String;
        final tokenAmount = data['tokenAmount'];
        final amount = tokenAmount['amount'] as String;
        final decimals = tokenAmount['decimals'] as int;

        accounts.add(SplTokenAccount(
          mint: mint,
          tokenAccount: pubkey,
          balance: BigInt.parse(amount),
          decimals: decimals,
        ));
      }

      AppLogger.d(
        'Fetched ${accounts.length} token accounts for $address on ${chain.name}',
      );
      return accounts;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get token accounts', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch token accounts from ${chain.name}',
        originalException: e,
      );
    }
  }

  @override
  Future<SplTokenInfo> getTokenInfo(String mintAddress, ChainInfo chain) async {
    // Check cache first
    if (_tokenMetadataCache.containsKey(mintAddress)) {
      return _tokenMetadataCache[mintAddress]!;
    }

    try {
      // Get mint account info for decimals
      final result = await _rpcCall(
        chain.rpcUrl,
        'getAccountInfo',
        [
          mintAddress,
          {'encoding': 'jsonParsed'},
        ],
      );

      int decimals = 9; // Default for SPL tokens

      if (result != null && result['value'] != null) {
        final data = result['value']['data'];
        if (data is Map && data.containsKey('parsed')) {
          final parsed = data['parsed'];
          if (parsed is Map && parsed.containsKey('info')) {
            final info = parsed['info'];
            if (info is Map && info.containsKey('decimals')) {
              decimals = info['decimals'] as int;
            }
          }
        }
      }

      // Resolve token metadata
      final info = _resolveTokenMetadata(mintAddress, decimals);
      _tokenMetadataCache[mintAddress] = info;

      AppLogger.d('Fetched token info for $mintAddress: ${info.symbol}');
      return info;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get token info', e, stackTrace);
      throw BalanceException(
        message: 'Failed to fetch token info from ${chain.name}',
        originalException: e,
      );
    }
  }

  /// Resolve token metadata from known tokens or use defaults
  SplTokenInfo _resolveTokenMetadata(String mintAddress, int decimals) {
    // Known popular SPL tokens
    const knownTokens = <String, Map<String, dynamic>>{
      // USDC
      'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v': {
        'symbol': 'USDC',
        'name': 'USD Coin',
        'decimals': 6,
      },
      // USDT
      'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB': {
        'symbol': 'USDT',
        'name': 'Tether USD',
        'decimals': 6,
      },
      // Wrapped SOL
      'So11111111111111111111111111111111111111112': {
        'symbol': 'WSOL',
        'name': 'Wrapped SOL',
        'decimals': 9,
      },
      // Raydium
      '4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R': {
        'symbol': 'RAY',
        'name': 'Raydium',
        'decimals': 6,
      },
      // Serum
      'SRMuApVNdxXokk5GT7XD5cUUgXMBCoAz2LHeuAoKWRt': {
        'symbol': 'SRM',
        'name': 'Serum',
        'decimals': 6,
      },
      // Bonk
      'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263': {
        'symbol': 'BONK',
        'name': 'Bonk',
        'decimals': 5,
      },
      // Jupiter
      'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN': {
        'symbol': 'JUP',
        'name': 'Jupiter',
        'decimals': 6,
      },
    };

    if (knownTokens.containsKey(mintAddress)) {
      final token = knownTokens[mintAddress]!;
      return SplTokenInfo(
        mint: mintAddress,
        symbol: token['symbol'] as String,
        name: token['name'] as String,
        decimals: token['decimals'] as int,
      );
    }

    // Unknown token - use shortened address as identifier
    final shortAddress =
        '${mintAddress.substring(0, 4)}...${mintAddress.substring(mintAddress.length - 4)}';
    return SplTokenInfo(
      mint: mintAddress,
      symbol: shortAddress,
      name: 'Unknown Token',
      decimals: decimals,
    );
  }

  @override
  void dispose() {
    _httpClient.close();
    _tokenMetadataCache.clear();
  }
}
