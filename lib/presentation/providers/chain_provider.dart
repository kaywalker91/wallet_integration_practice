import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';

/// Provider for selected chain (Riverpod 3.0 compatible)
final selectedChainProvider = StateProvider<ChainInfo>((ref) {
  return SupportedChains.ethereumSepolia; // Default to testnet
});

/// Provider for available EVM chains
final evmChainsProvider = Provider<List<ChainInfo>>((ref) {
  return SupportedChains.evmChains;
});

/// Provider for available Solana clusters
final solanaChainsProvider = Provider<List<ChainInfo>>((ref) {
  return SupportedChains.solanaChains;
});

/// Provider for all supported chains
final allChainsProvider = Provider<List<ChainInfo>>((ref) {
  return SupportedChains.all;
});

/// Provider for testnet-only chains
final testnetChainsProvider = Provider<List<ChainInfo>>((ref) {
  return SupportedChains.all.where((c) => c.isTestnet).toList();
});

/// Provider for mainnet-only chains
final mainnetChainsProvider = Provider<List<ChainInfo>>((ref) {
  return SupportedChains.all.where((c) => !c.isTestnet).toList();
});

/// Provider for chain by ID
final chainByIdProvider = Provider.family<ChainInfo?, int>((ref, chainId) {
  return SupportedChains.getByChainId(chainId);
});

/// Notifier for chain selection (Riverpod 3.0 - uses Notifier instead of StateNotifier)
class ChainSelectionNotifier extends Notifier<ChainInfo> {
  @override
  ChainInfo build() {
    return SupportedChains.ethereumSepolia;
  }

  void selectChain(ChainInfo chain) {
    state = chain;
  }

  void selectByChainId(int chainId) {
    final chain = SupportedChains.getByChainId(chainId);
    if (chain != null) {
      state = chain;
    }
  }
}

/// Provider for chain selection notifier (Riverpod 3.0 - uses NotifierProvider)
final chainSelectionProvider =
    NotifierProvider<ChainSelectionNotifier, ChainInfo>(
  ChainSelectionNotifier.new,
);
