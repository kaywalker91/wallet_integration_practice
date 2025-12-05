import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';

/// Base class for wallet adapters
abstract class BaseWalletAdapter {
  /// Wallet type identifier
  WalletType get walletType;

  /// Check if adapter is initialized
  bool get isInitialized;

  /// Check if connected
  bool get isConnected;

  /// Get connected address
  String? get connectedAddress;

  /// Get current chain ID
  int? get currentChainId;

  /// Initialize the adapter
  Future<void> initialize();

  /// Connect to wallet
  Future<WalletEntity> connect({
    int? chainId,
    String? cluster,
  });

  /// Disconnect from wallet
  Future<void> disconnect();

  /// Get connection URI for QR code
  Future<String?> getConnectionUri();

  /// Switch to a different chain
  Future<void> switchChain(int chainId);

  /// Send transaction
  Future<String> sendTransaction(TransactionRequest request);

  /// Sign personal message
  Future<String> personalSign(String message, String address);

  /// Sign typed data (EIP-712)
  Future<String> signTypedData(String address, Map<String, dynamic> typedData);

  /// Dispose resources
  Future<void> dispose();

  /// Stream of connection events
  Stream<WalletConnectionStatus> get connectionStream;
}

/// Abstract class for EVM-compatible wallet adapters
abstract class EvmWalletAdapter extends BaseWalletAdapter {
  /// Get current accounts
  Future<List<String>> getAccounts();

  /// Get current chain ID
  Future<int> getChainId();

  /// Add a new chain
  Future<void> addChain({
    required int chainId,
    required String chainName,
    required String rpcUrl,
    required String symbol,
    required int decimals,
    String? explorerUrl,
  });
}

/// Abstract class for Solana wallet adapters
abstract class SolanaWalletAdapter extends BaseWalletAdapter {
  /// Get current cluster
  String? get currentCluster;

  /// Sign Solana transaction
  Future<String> signSolanaTransaction(dynamic transaction);

  /// Sign multiple Solana transactions
  Future<List<String>> signAllTransactions(List<dynamic> transactions);

  /// Sign and send Solana transaction
  Future<String> signAndSendTransaction(dynamic transaction);
}
