import 'package:dartz/dartz.dart';
import 'package:wallet_integration_practice/core/errors/failures.dart';
import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/repositories/wallet_repository.dart';

/// Use case for connecting to a wallet
class ConnectWalletUseCase {
  final WalletRepository _repository;

  ConnectWalletUseCase(this._repository);

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
  final WalletRepository _repository;

  DisconnectWalletUseCase(this._repository);

  Future<Either<Failure, void>> call() async {
    return _repository.disconnect();
  }
}

/// Use case for getting current connected wallet
class GetConnectedWalletUseCase {
  final WalletRepository _repository;

  GetConnectedWalletUseCase(this._repository);

  Future<Either<Failure, WalletEntity?>> call() async {
    return _repository.getConnectedWallet();
  }
}

/// Use case for switching chain
class SwitchChainUseCase {
  final WalletRepository _repository;

  SwitchChainUseCase(this._repository);

  Future<Either<Failure, void>> call(int chainId) async {
    return _repository.switchChain(chainId);
  }
}

/// Use case for getting connection URI
class GetConnectionUriUseCase {
  final WalletRepository _repository;

  GetConnectionUriUseCase(this._repository);

  Future<Either<Failure, String>> call() async {
    return _repository.getConnectionUri();
  }
}
