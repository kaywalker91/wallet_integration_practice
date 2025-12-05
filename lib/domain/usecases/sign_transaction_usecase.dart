import 'package:dartz/dartz.dart';
import 'package:wallet_integration_practice/core/errors/failures.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/repositories/wallet_repository.dart';

/// Use case for sending a transaction
class SendTransactionUseCase {
  final TransactionRepository _repository;

  SendTransactionUseCase(this._repository);

  Future<Either<Failure, TransactionResult>> call(
    TransactionRequest request,
  ) async {
    return _repository.sendTransaction(request);
  }
}

/// Use case for personal sign
class PersonalSignUseCase {
  final TransactionRepository _repository;

  PersonalSignUseCase(this._repository);

  Future<Either<Failure, SignatureResult>> call(
    PersonalSignRequest request,
  ) async {
    return _repository.personalSign(request);
  }
}

/// Use case for signing typed data (EIP-712)
class SignTypedDataUseCase {
  final TransactionRepository _repository;

  SignTypedDataUseCase(this._repository);

  Future<Either<Failure, SignatureResult>> call(
    TypedDataSignRequest request,
  ) async {
    return _repository.signTypedData(request);
  }
}
