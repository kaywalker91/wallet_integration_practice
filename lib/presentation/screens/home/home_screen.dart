import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/balance_provider.dart';
import 'package:wallet_integration_practice/presentation/screens/onboarding/onboarding_loading_page.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/wallet_card.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/wallet_selector.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/connected_wallets_section.dart';
import 'package:wallet_integration_practice/presentation/pages/wallet_connect_modal.dart';

/// Main home screen
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallet Integration Practice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // Navigate to settings
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Refresh wallet connection status
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Active wallet display (Hero section - most important)
              Consumer(
                builder: (context, ref, _) {
                  final activeEntry = ref.watch(activeWalletEntryProvider);

                  if (activeEntry != null) {
                    final wallet = activeEntry.wallet;

                    // Get token symbol from wallet's own chainId/cluster
                    final tokenSymbol = _getTokenSymbol(wallet);

                    // Watch actual balance from blockchain
                    final balanceAsync = ref.watch(currentChainBalanceProvider);

                    // Log for debugging
                    AppLogger.d(
                        '[DEBUG] HomeScreen: balanceAsync state = ${balanceAsync.isLoading ? "loading" : balanceAsync.hasError ? "error" : "data"}');

                    final balance = balanceAsync.whenOrNull(
                      data: (entity) {
                        AppLogger.d(
                            '[DEBUG] HomeScreen: balance entity = $entity');
                        return entity?.balanceFormatted;
                      },
                    );

                    return WalletCard(
                      wallet: wallet,
                      onDisconnect: () =>
                          _disconnectActiveWallet(activeEntry.id),
                      // Chain switching removed - wallet auto-connects to default chain
                      balance: balance,
                      tokenSymbol: tokenSymbol,
                      onSignMessage: () => _signMessage(context),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              const SizedBox(height: 16),

              // 2. Connected wallets section (multi-wallet list)
              ConnectedWalletsSection(
                onConnectAnother: () => _showWalletSelector(context),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWalletSelector(BuildContext context) async {
    // Show wallet selector directly (chain is auto-determined by wallet type)
    await WalletSelector.show(
      context,
      onWalletSelected: (wallet) => _connectWallet(wallet),
    );
  }

  Future<void> _connectWallet(WalletInfo wallet) async {
    if (wallet.type == WalletType.walletConnect) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const WalletConnectModal(),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OnboardingLoadingPage(
            walletType: wallet.type,
          ),
        ),
      );
    }
  }


  Future<void> _disconnectActiveWallet(String walletId) async {
    await ref
        .read(multiWalletNotifierProvider.notifier)
        .disconnectWallet(walletId);
  }

  Future<void> _signMessage(BuildContext context) async {
    // Get the active account address (from session accounts or wallet)
    final transactionAddress = ref.read(transactionAddressProvider);
    if (transactionAddress == null) return;

    // Show sign message dialog
    final message = await showDialog<String>(
      context: context,
      builder: (context) => const _SignMessageDialog(),
    );

    if (message != null && message.isNotEmpty) {
      try {
        final service = ref.read(walletServiceProvider);
        final result = await service.personalSign(
          PersonalSignRequest(
            message: message,
            address: transactionAddress,
          ),
        );

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Signed! Signature: ${AddressUtils.truncate(result.signature, start: 10, end: 10)}',
            ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Signing failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Get token symbol from wallet's chainId or cluster
  String _getTokenSymbol(WalletEntity wallet) {
    if (wallet.chainId != null) {
      final chain = SupportedChains.getByChainId(wallet.chainId!);
      if (chain != null) return chain.symbol;
    }
    if (wallet.cluster != null) {
      // Solana clusters
      return 'SOL';
    }
    return 'ETH'; // default fallback
  }
}

class _SignMessageDialog extends StatefulWidget {
  const _SignMessageDialog();

  @override
  State<_SignMessageDialog> createState() => _SignMessageDialogState();
}

class _SignMessageDialogState extends State<_SignMessageDialog> {
  final _controller = TextEditingController(
    text: 'Hello from Wallet Integration Practice!',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign Message'),
      content: TextField(
        controller: _controller,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Enter message to sign',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Sign'),
        ),
      ],
    );
  }
}
