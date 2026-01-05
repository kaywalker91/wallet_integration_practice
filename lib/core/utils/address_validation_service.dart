import 'package:equatable/equatable.dart';

import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/utils/address_utils.dart';

/// Centralized address validation service with chain-type awareness
///
/// This service validates that wallet addresses match the expected chain type
/// before making RPC calls to prevent "Invalid param" errors.
///
/// Example:
/// ```dart
/// final result = AddressValidationService.validateForChain(
///   address: '0x742d35Cc6634C0532925a3b844Bc9e7595f8e41a',
///   chainType: ChainType.evm,
/// );
/// if (result.isValid) {
///   // Proceed with RPC call
/// } else {
///   // Handle validation error
/// }
/// ```
class AddressValidationService {
  AddressValidationService._();

  /// Validates address format matches the expected chain type
  ///
  /// Returns [AddressValidationResult] with isValid=true if the address
  /// format matches the chain type, otherwise returns a descriptive error.
  static AddressValidationResult validateForChain({
    required String address,
    required ChainType chainType,
  }) {
    if (address.isEmpty) {
      return AddressValidationResult.invalid(
        AddressValidationError.empty(),
      );
    }

    switch (chainType) {
      case ChainType.evm:
        if (!AddressUtils.isValidEvmAddress(address)) {
          // Check if it looks like a Solana address instead
          final detectedType = detectChainType(address);
          return AddressValidationResult.invalid(
            AddressValidationError.formatMismatch(
              expected: 'EVM (0x + 40 hex chars)',
              received: _truncateForLog(address),
              chainType: chainType,
              detectedChainType: detectedType,
            ),
          );
        }
        return AddressValidationResult.valid(address);

      case ChainType.solana:
        if (!AddressUtils.isValidSolanaAddress(address)) {
          // Check if it looks like an EVM address instead
          final detectedType = detectChainType(address);
          return AddressValidationResult.invalid(
            AddressValidationError.formatMismatch(
              expected: 'Solana (32-44 Base58 chars)',
              received: _truncateForLog(address),
              chainType: chainType,
              detectedChainType: detectedType,
            ),
          );
        }
        return AddressValidationResult.valid(address);

      case ChainType.sui:
        // Sui addresses start with 0x like EVM but have different length (66 chars)
        // For now, accept EVM-like addresses for Sui
        // TODO: Add proper Sui address validation when implementing Sui support
        return AddressValidationResult.valid(address);
    }
  }

  /// Detects chain type from address format
  ///
  /// Returns null if the address format doesn't match any known chain type.
  static ChainType? detectChainType(String address) {
    if (address.isEmpty) return null;

    // EVM: 0x + 40 hex characters = 42 total
    if (AddressUtils.isValidEvmAddress(address)) {
      return ChainType.evm;
    }

    // Solana: 32-44 Base58 characters
    if (AddressUtils.isValidSolanaAddress(address)) {
      return ChainType.solana;
    }

    return null;
  }

  /// Checks if an address could be valid for any supported chain
  static bool isValidForAnyChain(String address) {
    return detectChainType(address) != null;
  }

  /// Truncates address for logging (security: don't log full addresses)
  static String _truncateForLog(String address) {
    if (address.length <= 12) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

/// Result of address validation
class AddressValidationResult {
  const AddressValidationResult._({
    required this.isValid,
    this.validatedAddress,
    this.error,
  });

  /// Creates a valid result with the validated address
  factory AddressValidationResult.valid(String address) {
    return AddressValidationResult._(
      isValid: true,
      validatedAddress: address,
    );
  }

  /// Creates an invalid result with the validation error
  factory AddressValidationResult.invalid(AddressValidationError error) {
    return AddressValidationResult._(
      isValid: false,
      error: error,
    );
  }

  /// Whether the address is valid for the specified chain type
  final bool isValid;

  /// The validated address (only set when isValid is true)
  final String? validatedAddress;

  /// The validation error (only set when isValid is false)
  final AddressValidationError? error;

  @override
  String toString() {
    if (isValid) {
      return 'AddressValidationResult(valid: $validatedAddress)';
    }
    return 'AddressValidationResult(invalid: ${error?.message})';
  }
}

/// Typed validation error for address format mismatches
class AddressValidationError extends Equatable {
  const AddressValidationError._({
    required this.message,
    required this.code,
    this.expected,
    this.received,
    this.chainType,
    this.detectedChainType,
  });

  /// Creates an error for empty address
  factory AddressValidationError.empty() {
    return const AddressValidationError._(
      message: 'Address cannot be empty',
      code: 'EMPTY_ADDRESS',
    );
  }

  /// Creates an error for address format mismatch
  factory AddressValidationError.formatMismatch({
    required String expected,
    required String received,
    required ChainType chainType,
    ChainType? detectedChainType,
  }) {
    final detectedHint = detectedChainType != null
        ? ' (looks like ${detectedChainType.name} address)'
        : '';
    return AddressValidationError._(
      message:
          'Address format mismatch for ${chainType.name}: expected $expected, got $received$detectedHint',
      code: 'FORMAT_MISMATCH',
      expected: expected,
      received: received,
      chainType: chainType,
      detectedChainType: detectedChainType,
    );
  }

  /// Human-readable error message
  final String message;

  /// Error code for programmatic handling
  final String code;

  /// Expected format description (optional)
  final String? expected;

  /// Received address (truncated for security)
  final String? received;

  /// Target chain type that was being validated against
  final ChainType? chainType;

  /// Detected chain type from address format (if any)
  final ChainType? detectedChainType;

  @override
  List<Object?> get props =>
      [message, code, expected, received, chainType, detectedChainType];

  @override
  String toString() => 'AddressValidationError($code: $message)';
}
