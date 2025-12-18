import 'dart:async';
import 'dart:convert';
import 'package:coinbase_wallet_sdk/action.dart' as cb;
import 'package:coinbase_wallet_sdk/coinbase_wallet_sdk.dart' as cb;
import 'package:coinbase_wallet_sdk/configuration.dart' as cb;
import 'package:coinbase_wallet_sdk/currency.dart' as cb;
import 'package:coinbase_wallet_sdk/eth_web3_rpc.dart' as cb;
import 'package:coinbase_wallet_sdk/request.dart' as cb;
import 'package:coinbase_wallet_sdk/return_value.dart' as cb;
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';

class CoinbaseWalletAdapter extends EvmWalletAdapter {
  final WalletAdapterConfig config;
  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();

  bool _isInitialized = false;
  WalletEntity? _connectedWallet;
  String? _currentAddress;
  int _currentChainId = 1; // Default to mainnet

  CoinbaseWalletAdapter({required this.config});

  @override
  WalletType get walletType => WalletType.coinbase;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isConnected => _connectedWallet != null;

  @override
  String? get connectedAddress => _currentAddress;

  @override
  int? get currentChainId => _currentChainId;

  @override
  Stream<WalletConnectionStatus> get connectionStream => _connectionController.stream;

  @override
  Future<void> initialize() async {
    try {
      await cb.CoinbaseWalletSDK.shared.configure(
        cb.Configuration(
          ios: cb.IOSConfiguration(
            host: Uri.parse('${AppConstants.deepLinkScheme}://'),
            callback: Uri.parse('${AppConstants.deepLinkScheme}://'),
          ),
          android: cb.AndroidConfiguration(
            domain: Uri.parse('${AppConstants.deepLinkScheme}://'),
          ),
        ),
      );
      _isInitialized = true;
      AppLogger.wallet('Coinbase SDK initialized');
    } catch (e) {
      AppLogger.e('Failed to initialize Coinbase SDK', e);
    }
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    _connectionController.add(WalletConnectionStatus.connecting());

    try {
      AppLogger.wallet('Initiating Coinbase SDK Handshake');

      final actions = <cb.Action>[
        const cb.RequestAccounts(),
      ];

      final results = await cb.CoinbaseWalletSDK.shared.initiateHandshake(actions);

      if (results.isEmpty) {
        throw Exception('Handshake returned no results');
      }

      final accountResult = results.first;

      if (accountResult.error != null) {
        throw Exception('Coinbase error: ${accountResult.error?.message}');
      }

      final dynamic value = accountResult.value;
      String address;

      if (value is List) {
        if (value.isEmpty) {
          throw Exception('Handshake returned empty accounts list');
        }
        address = value.first.toString();
      } else if (value is Map) {
        if (value.containsKey('address')) {
           address = value['address'].toString();
           if (value.containsKey('networkId')) {
             _currentChainId = int.tryParse(value['networkId'].toString()) ?? 1;
           }
        } else {
           throw Exception('Map result missing "address" key: $value');
        }
      } else if (value is String) {
        if (value.trim().startsWith('{')) {
           try {
             final Map<String, dynamic> jsonMap = jsonDecode(value);
             if (jsonMap.containsKey('address')) {
                address = jsonMap['address'].toString();
                if (jsonMap.containsKey('networkId')) {
                  _currentChainId = int.tryParse(jsonMap['networkId'].toString()) ?? 1;
                }
             } else {
                address = value; // Fallback
             }
           } catch (e) {
             address = value;
           }
        } else {
             address = value;
        }
      } else {
         AppLogger.wallet('Parsing Coinbase result value: $value (${value.runtimeType})');
         if (value.toString().startsWith('0x')) {
            address = value.toString();
         } else {
            throw Exception('Unexpected account result format: $value');
         }
      }

      _currentAddress = address;
      _currentChainId = chainId ?? 1;

      final wallet = WalletEntity(
        address: address,
        type: walletType,
        chainId: _currentChainId,
        connectedAt: DateTime.now(),
      );

      _connectedWallet = wallet;
      _connectionController.add(WalletConnectionStatus.connected(wallet));
      AppLogger.wallet('Coinbase connected via SDK: $address');
      
      return wallet;

    } catch (e) {
      AppLogger.e('Coinbase connection failed', e);
      _connectionController.add(WalletConnectionStatus.error(e.toString()));
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await cb.CoinbaseWalletSDK.shared.resetSession();
    } catch (e) {
         AppLogger.e('Error resetting session', e);
    }
    
    _connectedWallet = null;
    _currentAddress = null;
    _connectionController.add(WalletConnectionStatus.disconnected());
    AppLogger.wallet('Coinbase disconnected');
  }

  @override
  Future<String?> getConnectionUri() async {
    // Native SDK handles UI, no URI to display
    return null;
  }

  @override
  Future<List<String>> getAccounts() async {
    return _currentAddress != null ? [_currentAddress!] : [];
  }

  @override
  Future<int> getChainId() async {
    return _currentChainId;
  }
  
  // -- EVM Wallet Methods --

  @override
  Future<void> addChain({
    required int chainId,
    required String chainName,
    required String rpcUrl,
    required String symbol,
    required int decimals,
    String? explorerUrl,
  }) async {
    _ensureConnected();

    final chainIdHex = '0x${chainId.toRadixString(16)}';
    final action = cb.AddEthereumChain(
      chainId: chainIdHex,
      chainName: chainName,
      rpcUrls: [rpcUrl],
      nativeCurrency: cb.Currency(
        name: symbol,
        symbol: symbol,
        decimals: decimals,
      ),
      blockExplorerUrls: explorerUrl != null ? [explorerUrl] : null,
    );

    final request = cb.Request(actions: [action]);

    try {
      final results = await cb.CoinbaseWalletSDK.shared.makeRequest(request);
      _handleRequestResult(results, 'addChain');
      AppLogger.wallet('Chain added successfully', data: {'chainId': chainId});
    } catch (e) {
      AppLogger.e('Failed to add chain', e);
      throw WalletException(
        message: 'Failed to add chain: ${e.toString()}',
        code: 'ADD_CHAIN_FAILED',
      );
    }
  }

  @override
  Future<void> switchChain(int chainId) async {
    _ensureConnected();

    final chainIdHex = '0x${chainId.toRadixString(16)}';
    final action = cb.SwitchEthereumChain(chainId: chainIdHex);
    final request = cb.Request(actions: [action]);

    try {
      final results = await cb.CoinbaseWalletSDK.shared.makeRequest(request);
      _handleRequestResult(results, 'switchChain');
      _currentChainId = chainId;

      // Update connected wallet with new chain
      if (_connectedWallet != null) {
        _connectedWallet = _connectedWallet!.copyWith(chainId: chainId);
        _connectionController.add(WalletConnectionStatus.connected(_connectedWallet!));
      }

      AppLogger.wallet('Chain switched successfully', data: {'chainId': chainId});
    } catch (e) {
      AppLogger.e('Failed to switch chain', e);
      throw WalletException(
        message: 'Failed to switch chain: ${e.toString()}',
        code: 'SWITCH_CHAIN_FAILED',
      );
    }
  }

  @override
  Future<String> sendTransaction(TransactionRequest request) async {
    _ensureConnected();

    final chainIdHex = '0x${request.chainId.toRadixString(16)}';

    final action = cb.SendTransaction(
      fromAddress: _currentAddress!,
      toAddress: request.to,
      chainId: chainIdHex,
      weiValue: request.value,
      data: request.data,
      gasLimit: request.gasLimit,
      maxFeePerGas: request.maxFeePerGas,
      maxPriorityFeePerGas: request.maxPriorityFeePerGas,
      nonce: request.nonce,
    );

    final cbRequest = cb.Request(actions: [action]);

    try {
      final results = await cb.CoinbaseWalletSDK.shared.makeRequest(cbRequest);
      final txHash = _handleRequestResult(results, 'sendTransaction');

      AppLogger.wallet('Transaction sent', data: {
        'txHash': txHash,
        'to': request.to,
        'chainId': request.chainId,
      });

      return txHash;
    } catch (e) {
      AppLogger.e('Failed to send transaction', e);
      throw WalletException(
        message: 'Failed to send transaction: ${e.toString()}',
        code: 'SEND_TX_FAILED',
      );
    }
  }

  @override
  Future<String> personalSign(String message, String address) async {
    _ensureConnected();

    // Convert message to hex if it's not already
    final hexMessage = message.startsWith('0x')
        ? message
        : '0x${message.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';

    final action = cb.PersonalSign(
      address: address,
      message: hexMessage,
    );

    final request = cb.Request(actions: [action]);

    try {
      final results = await cb.CoinbaseWalletSDK.shared.makeRequest(request);
      final signature = _handleRequestResult(results, 'personalSign');

      AppLogger.wallet('Message signed', data: {
        'address': address,
        'signature': '${signature.substring(0, 20)}...',
      });

      return signature;
    } catch (e) {
      AppLogger.e('Failed to sign message', e);
      throw WalletException(
        message: 'Failed to sign message: ${e.toString()}',
        code: 'SIGN_FAILED',
      );
    }
  }

  @override
  Future<String> signTypedData(String address, Map<String, dynamic> typedData) async {
    _ensureConnected();

    final typedDataJson = jsonEncode(typedData);
    final action = cb.SignTypedDataV4(
      address: address,
      typedDataJson: typedDataJson,
    );

    final request = cb.Request(actions: [action]);

    try {
      final results = await cb.CoinbaseWalletSDK.shared.makeRequest(request);
      final signature = _handleRequestResult(results, 'signTypedData');

      AppLogger.wallet('Typed data signed', data: {
        'address': address,
        'signature': '${signature.substring(0, 20)}...',
      });

      return signature;
    } catch (e) {
      AppLogger.e('Failed to sign typed data', e);
      throw WalletException(
        message: 'Failed to sign typed data: ${e.toString()}',
        code: 'SIGN_TYPED_DATA_FAILED',
      );
    }
  }

  // -- Helper Methods --

  /// Ensures wallet is connected before making requests
  void _ensureConnected() {
    if (!isConnected || _currentAddress == null) {
      throw const WalletException(
        message: 'Wallet not connected',
        code: 'NOT_CONNECTED',
      );
    }
  }

  /// Handles SDK request results and extracts value or throws error
  String _handleRequestResult(List<cb.ReturnValue> results, String operation) {
    if (results.isEmpty) {
      throw WalletException(
        message: '$operation returned no results',
        code: 'EMPTY_RESULT',
      );
    }

    final result = results.first;

    if (result.error != null) {
      throw WalletException(
        message: '${result.error!.message} (code: ${result.error!.code})',
        code: 'COINBASE_ERROR',
      );
    }

    if (result.value == null || result.value!.isEmpty) {
      throw WalletException(
        message: '$operation returned empty value',
        code: 'EMPTY_VALUE',
      );
    }

    return result.value!;
  }

  @override
  Future<void> dispose() async {
    await _connectionController.close();
  }
}
