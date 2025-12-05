/// Utility functions for blockchain address handling
class AddressUtils {
  AddressUtils._();

  /// Truncate address for display (e.g., 0x1234...5678)
  static String truncate(String address, {int start = 6, int end = 4}) {
    if (address.length <= start + end) {
      return address;
    }
    return '${address.substring(0, start)}...${address.substring(address.length - end)}';
  }

  /// Validate Ethereum address format
  static bool isValidEvmAddress(String address) {
    if (!address.startsWith('0x')) {
      return false;
    }
    if (address.length != 42) {
      return false;
    }
    final hexPart = address.substring(2);
    final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
    return hexRegex.hasMatch(hexPart);
  }

  /// Validate Solana address format (Base58)
  static bool isValidSolanaAddress(String address) {
    if (address.length < 32 || address.length > 44) {
      return false;
    }
    final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    return base58Regex.hasMatch(address);
  }

  /// Convert address to checksum format (EIP-55)
  static String toChecksumAddress(String address) {
    if (!isValidEvmAddress(address)) {
      return address;
    }
    // For now, return lowercase. Full implementation would require keccak256
    return address.toLowerCase();
  }

  /// Compare two addresses (case-insensitive for EVM)
  static bool areEqual(String address1, String address2) {
    return address1.toLowerCase() == address2.toLowerCase();
  }
}
