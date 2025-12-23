import 'package:equatable/equatable.dart';

/// Transaction request entity
class TransactionRequest extends Equatable {
  const TransactionRequest({
    required this.from,
    required this.to,
    required this.value,
    this.data,
    this.gasLimit,
    this.gasPrice,
    this.maxFeePerGas,
    this.maxPriorityFeePerGas,
    this.nonce,
    required this.chainId,
  });

  final String from;
  final String to;
  final BigInt value;
  final String? data;
  final BigInt? gasLimit;
  final BigInt? gasPrice;
  final BigInt? maxFeePerGas;
  final BigInt? maxPriorityFeePerGas;
  final int? nonce;
  final int chainId;

  /// Convert to Map for WalletConnect
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'from': from,
      'to': to,
      'value': '0x${value.toRadixString(16)}',
    };

    if (data != null) map['data'] = data;
    if (gasLimit != null) map['gas'] = '0x${gasLimit!.toRadixString(16)}';
    if (gasPrice != null) {
      map['gasPrice'] = '0x${gasPrice!.toRadixString(16)}';
    }
    if (maxFeePerGas != null) {
      map['maxFeePerGas'] = '0x${maxFeePerGas!.toRadixString(16)}';
    }
    if (maxPriorityFeePerGas != null) {
      map['maxPriorityFeePerGas'] =
          '0x${maxPriorityFeePerGas!.toRadixString(16)}';
    }
    if (nonce != null) map['nonce'] = '0x${nonce!.toRadixString(16)}';

    return map;
  }

  @override
  List<Object?> get props => [
        from,
        to,
        value,
        data,
        gasLimit,
        gasPrice,
        maxFeePerGas,
        maxPriorityFeePerGas,
        nonce,
        chainId,
      ];
}

/// Transaction result entity
class TransactionResult extends Equatable {
  const TransactionResult({
    required this.hash,
    required this.status,
    required this.timestamp,
    this.errorMessage,
  });

  final String hash;
  final TransactionStatus status;
  final DateTime timestamp;
  final String? errorMessage;

  bool get isSuccess => status == TransactionStatus.success;
  bool get isPending => status == TransactionStatus.pending;
  bool get isFailed => status == TransactionStatus.failed;

  @override
  List<Object?> get props => [hash, status, timestamp, errorMessage];
}

/// Transaction status
enum TransactionStatus {
  pending,
  success,
  failed,
}

/// Personal sign request
class PersonalSignRequest extends Equatable {
  const PersonalSignRequest({
    required this.message,
    required this.address,
  });

  final String message;
  final String address;

  @override
  List<Object?> get props => [message, address];
}

/// Typed data sign request (EIP-712)
class TypedDataSignRequest extends Equatable {
  const TypedDataSignRequest({
    required this.address,
    required this.typedData,
  });

  final String address;
  final Map<String, dynamic> typedData;

  @override
  List<Object?> get props => [address, typedData];
}

/// Signature result
class SignatureResult extends Equatable {
  const SignatureResult({
    required this.signature,
    required this.timestamp,
  });

  final String signature;
  final DateTime timestamp;

  @override
  List<Object?> get props => [signature, timestamp];
}
