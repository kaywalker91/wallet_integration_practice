import 'dart:async';
import 'dart:convert';
import 'package:coinbase_wallet_sdk/action.dart' as cb;
import 'package:coinbase_wallet_sdk/coinbase_wallet_sdk.dart' as cb;
import 'package:coinbase_wallet_sdk/configuration.dart' as cb;
import 'package:coinbase_wallet_sdk/eth_web3_rpc.dart' as cb;
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
  
  // -- Unimplemented / To Do methods --

  @override
  Future<void> addChain({
    required int chainId,
    required String chainName,
    required String rpcUrl,
    required String symbol,
    required int decimals,
    String? explorerUrl,
  }) async {
    // Implement using 'wallet_addEthereumChain' action if needed
    throw UnimplementedError('addChain not implemented for Coinbase SDK yet');
  }

  @override
  Future<void> switchChain(int chainId) async {
    // Implement using 'wallet_switchEthereumChain' action
    // await CoinbaseWalletSDK.shared.makeRequest(...)
    _currentChainId = chainId; // Optimistic update
    throw UnimplementedError('switchChain not implemented for Coinbase SDK yet');
  }

  @override
  Future<String> sendTransaction(TransactionRequest request) async {
    // Implement using 'eth_sendTransaction' action
    throw UnimplementedError('sendTransaction not implemented for Coinbase SDK yet');
  }

  @override
  Future<String> personalSign(String message, String address) async {
    // Implement using 'personal_sign' action
     throw UnimplementedError('personalSign not implemented for Coinbase SDK yet');
  }

  @override
  Future<String> signTypedData(String address, Map<String, dynamic> typedData) async {
    // Implement using 'eth_signTypedData_v4' action
    throw UnimplementedError('signTypedData not implemented for Coinbase SDK yet');
  }

  @override
  Future<void> dispose() async {
    await _connectionController.close();
  }
}
