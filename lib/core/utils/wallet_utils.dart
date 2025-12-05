import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';

/// Utility functions for wallet-related operations
class WalletUtils {
  WalletUtils._();

  /// Copy text to clipboard
  /// Returns true if successful, false otherwise
  static Future<bool> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    } catch (e) {
      // Log error but don't throw - clipboard operations may fail silently
      return false;
    }
  }

  /// Get network display name from chainId
  static String getNetworkName(int? chainId, String? cluster) {
    if (chainId != null) {
      final chain = SupportedChains.getByChainId(chainId);
      if (chain != null) {
        return chain.name;
      }
      // Fallback for unknown chain IDs
      return 'Chain $chainId';
    }
    if (cluster != null) {
      // Solana clusters
      switch (cluster) {
        case ChainConstants.solanaMainnet:
          return 'Solana';
        case ChainConstants.solanaDevnet:
          return 'Solana Devnet';
        case ChainConstants.solanaTestnet:
          return 'Solana Testnet';
        default:
          return cluster;
      }
    }
    return 'Unknown Network';
  }

  /// Format DateTime for display in wallet cards
  /// Format: "2025 Sep 12 22:46:30"
  static String formatConnectedDate(DateTime dateTime) {
    final formatter = DateFormat('yyyy MMM dd HH:mm:ss');
    return formatter.format(dateTime);
  }

  /// Mask sensitive text with asterisks
  /// Returns a string of asterisks matching the pattern
  static String maskText(String text, {int length = 10}) {
    return '*' * length;
  }

  /// Mask balance/token value
  static String maskBalance() {
    return '*' * 12;
  }

  /// Format token balance for display
  /// Placeholder implementation - actual balance would come from blockchain data
  static String formatTokenBalance(double? balance) {
    if (balance == null) {
      return '\$0.00';
    }
    final formatter = NumberFormat.currency(
      symbol: '\$',
      decimalDigits: 2,
    );
    return formatter.format(balance);
  }
}
