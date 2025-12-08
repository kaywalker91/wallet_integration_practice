/// Base exception class
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalException;

  const AppException({
    required this.message,
    this.code,
    this.originalException,
  });

  @override
  String toString() => 'AppException: $message (code: $code)';
}

/// Wallet-related exceptions
class WalletException extends AppException {
  const WalletException({
    required super.message,
    super.code,
    super.originalException,
  });
}

/// Network-related exceptions
class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.code,
    super.originalException,
  });
}

/// Storage-related exceptions
class StorageException extends AppException {
  const StorageException({
    required super.message,
    super.code,
    super.originalException,
  });
}

/// Chain-related exceptions
class ChainException extends AppException {
  const ChainException({
    required super.message,
    super.code,
    super.originalException,
  });
}

/// Balance-related exceptions
class BalanceException extends AppException {
  const BalanceException({
    required super.message,
    super.code,
    super.originalException,
  });
}
