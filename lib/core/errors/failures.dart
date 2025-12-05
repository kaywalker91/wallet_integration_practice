import 'package:equatable/equatable.dart';

/// Base failure class for error handling
abstract class Failure extends Equatable {
  final String message;
  final String? code;
  final dynamic originalError;

  const Failure({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  List<Object?> get props => [message, code];
}

/// Wallet connection failures
class WalletConnectionFailure extends Failure {
  const WalletConnectionFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory WalletConnectionFailure.timeout() {
    return const WalletConnectionFailure(
      message: 'Connection timed out. Please try again.',
      code: 'TIMEOUT',
    );
  }

  factory WalletConnectionFailure.rejected() {
    return const WalletConnectionFailure(
      message: 'Connection was rejected by the wallet.',
      code: 'REJECTED',
    );
  }

  factory WalletConnectionFailure.walletNotInstalled(String walletName) {
    return WalletConnectionFailure(
      message: '$walletName is not installed on this device.',
      code: 'NOT_INSTALLED',
    );
  }

  factory WalletConnectionFailure.sessionExpired() {
    return const WalletConnectionFailure(
      message: 'Session expired. Please reconnect.',
      code: 'SESSION_EXPIRED',
    );
  }

  factory WalletConnectionFailure.unknown(dynamic error) {
    return WalletConnectionFailure(
      message: 'Failed to connect wallet: ${error.toString()}',
      code: 'UNKNOWN',
      originalError: error,
    );
  }
}

/// Transaction signing failures
class SignatureFailure extends Failure {
  const SignatureFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory SignatureFailure.rejected() {
    return const SignatureFailure(
      message: 'Transaction was rejected by the user.',
      code: 'REJECTED',
    );
  }

  factory SignatureFailure.timeout() {
    return const SignatureFailure(
      message: 'Signature request timed out.',
      code: 'TIMEOUT',
    );
  }

  factory SignatureFailure.invalidParams() {
    return const SignatureFailure(
      message: 'Invalid transaction parameters.',
      code: 'INVALID_PARAMS',
    );
  }

  factory SignatureFailure.unknown(dynamic error) {
    return SignatureFailure(
      message: 'Signature failed: ${error.toString()}',
      code: 'UNKNOWN',
      originalError: error,
    );
  }
}

/// Network failures
class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory NetworkFailure.noConnection() {
    return const NetworkFailure(
      message: 'No internet connection.',
      code: 'NO_CONNECTION',
    );
  }

  factory NetworkFailure.serverError() {
    return const NetworkFailure(
      message: 'Server error. Please try again later.',
      code: 'SERVER_ERROR',
    );
  }

  factory NetworkFailure.timeout() {
    return const NetworkFailure(
      message: 'Request timed out.',
      code: 'TIMEOUT',
    );
  }
}

/// Chain related failures
class ChainFailure extends Failure {
  const ChainFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory ChainFailure.unsupportedChain(int chainId) {
    return ChainFailure(
      message: 'Chain ID $chainId is not supported.',
      code: 'UNSUPPORTED_CHAIN',
    );
  }

  factory ChainFailure.switchFailed() {
    return const ChainFailure(
      message: 'Failed to switch chain.',
      code: 'SWITCH_FAILED',
    );
  }
}

/// Storage failures
class StorageFailure extends Failure {
  const StorageFailure({
    required super.message,
    super.code,
    super.originalError,
  });

  factory StorageFailure.readFailed() {
    return const StorageFailure(
      message: 'Failed to read from storage.',
      code: 'READ_FAILED',
    );
  }

  factory StorageFailure.writeFailed() {
    return const StorageFailure(
      message: 'Failed to write to storage.',
      code: 'WRITE_FAILED',
    );
  }
}
