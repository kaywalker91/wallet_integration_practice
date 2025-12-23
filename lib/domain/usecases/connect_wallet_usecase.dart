import 'package:dartz/dartz.dart';
import 'package:wallet_integration_practice/core/errors/failures.dart';
import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/repositories/wallet_repository.dart';

/// Use case for connecting to a wallet
class ConnectWalletUseCase {
  ConnectWalletUseCase(this._repository);

  final WalletRepository _repository;

  Future<Either<Failure, WalletEntity>> call({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) async {
    return _repository.connect(
      walletType: walletType,
      chainId: chainId,
      cluster: cluster,
    );
  }
}

/// Use case for disconnecting from a wallet
class DisconnectWalletUseCase {
  DisconnectWalletUseCase(this._repository);

  final WalletRepository _repository;

  Future<Either<Failure, void>> call() async {
    return _repository.disconnect();
  }
}

/// Use case for getting current connected wallet
class GetConnectedWalletUseCase {
  GetConnectedWalletUseCase(this._repository);

  final WalletRepository _repository;

  Future<Either<Failure, WalletEntity?>> call() async {
    return _repository.getConnectedWallet();
  }
}

/// Use case for switching chain
class SwitchChainUseCase {
  SwitchChainUseCase(this._repository);

  final WalletRepository _repository;

  Future<Either<Failure, void>> call(int chainId) async {
    return _repository.switchChain(chainId);
  }
}

/// Use case for getting connection URI
class GetConnectionUriUseCase {
  GetConnectionUriUseCase(this._repository);

  final WalletRepository _repository;

  Future<Either<Failure, String>> call() async {
    return _repository.getConnectionUri();
  }
}
