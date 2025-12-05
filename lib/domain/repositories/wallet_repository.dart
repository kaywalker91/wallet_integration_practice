import 'package:dartz/dartz.dart';
import 'package:wallet_integration_practice/core/errors/failures.dart';
import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';

/// Abstract wallet repository interface
abstract class WalletRepository {
  /// Initialize wallet connection service
  Future<Either<Failure, void>> initialize();

  /// Connect to a wallet
  Future<Either<Failure, WalletEntity>> connect({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  });

  /// Disconnect from wallet
  Future<Either<Failure, void>> disconnect();

  /// Get current connected wallet
  Future<Either<Failure, WalletEntity?>> getConnectedWallet();

  /// Check if wallet is connected
  Future<bool> isConnected();

  /// Switch chain
  Future<Either<Failure, void>> switchChain(int chainId);

  /// Get connection URI for QR code display
  Future<Either<Failure, String>> getConnectionUri();

  /// Stream of wallet connection status
  Stream<WalletConnectionStatus> get connectionStatusStream;
}

/// Abstract transaction repository interface
abstract class TransactionRepository {
  /// Send transaction
  Future<Either<Failure, TransactionResult>> sendTransaction(
    TransactionRequest request,
  );

  /// Sign personal message
  Future<Either<Failure, SignatureResult>> personalSign(
    PersonalSignRequest request,
  );

  /// Sign typed data (EIP-712)
  Future<Either<Failure, SignatureResult>> signTypedData(
    TypedDataSignRequest request,
  );

  /// Get transaction by hash
  Future<Either<Failure, TransactionResult>> getTransaction(String hash);
}
