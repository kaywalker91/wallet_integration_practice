import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/chain_provider.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/wallet_card.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/wallet_selector.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/qr_code_display.dart';
import 'package:wallet_integration_practice/presentation/widgets/common/loading_overlay.dart';

/// Main home screen
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isConnecting = false;
  String? _connectionUri;

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletNotifierProvider);
    final selectedChain = ref.watch(chainSelectionProvider);

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
      body: LoadingOverlay(
        isLoading: _isConnecting,
        message: 'Connecting to wallet...',
        child: RefreshIndicator(
          onRefresh: () async {
            // Refresh wallet connection status
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Chain selector
                _ChainSelector(
                  selectedChain: selectedChain,
                  onChainSelected: (chain) {
                    ref.read(chainSelectionProvider.notifier).selectChain(chain);
                  },
                ),
                const SizedBox(height: 24),

                // Wallet connection section
                walletState.when(
                  data: (wallet) {
                    if (wallet != null) {
                      return Column(
                        children: [
                          WalletCard(
                            wallet: wallet,
                            onDisconnect: _disconnectWallet,
                            onSwitchChain: () => _showChainSelector(context),
                          ),
                          const SizedBox(height: 24),
                          _ActionButtons(
                            onSignMessage: () => _signMessage(context),
                            onSendTransaction: () => _sendTransaction(context),
                          ),
                        ],
                      );
                    } else {
                      return _ConnectWalletCard(
                        onConnect: () => _showWalletSelector(context),
                      );
                    }
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => _ErrorCard(
                    message: error.toString(),
                    onRetry: () => _showWalletSelector(context),
                  ),
                ),

                // QR Code display (if connecting via WalletConnect)
                if (_connectionUri != null) ...[
                  const SizedBox(height: 24),
                  QrCodeDisplay(uri: _connectionUri!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showWalletSelector(BuildContext context) async {
    await WalletSelector.show(
      context,
      onWalletSelected: (wallet) => _connectWallet(wallet),
    );
  }

  Future<void> _connectWallet(WalletInfo wallet) async {
    setState(() {
      _isConnecting = true;
      _connectionUri = null;
    });

    try {
      final selectedChain = ref.read(chainSelectionProvider);

      // Start connection
      ref.read(walletNotifierProvider.notifier).connect(
            walletType: wallet.type,
            chainId: selectedChain.chainId,
            cluster: selectedChain.cluster,
          );

      // Get connection URI for QR display
      final uri = await ref.read(walletNotifierProvider.notifier).getConnectionUri();
      if (uri != null) {
        setState(() {
          _connectionUri = uri;
        });
      }
    } catch (e) {
      AppLogger.e('Connection error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  Future<void> _disconnectWallet() async {
    await ref.read(walletNotifierProvider.notifier).disconnect();
    setState(() {
      _connectionUri = null;
    });
  }

  void _showChainSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _ChainSelectorSheet(
        onChainSelected: (chain) async {
          Navigator.pop(context);
          try {
            await ref.read(walletNotifierProvider.notifier).switchChain(
                  chain.chainId!,
                );
            ref.read(chainSelectionProvider.notifier).selectChain(chain);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to switch chain: ${e.toString()}'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _signMessage(BuildContext context) async {
    final wallet = ref.read(walletNotifierProvider).value;
    if (wallet == null) return;

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
            address: wallet.address,
          ),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Signed! Signature: ${AddressUtils.truncate(result.signature, start: 10, end: 10)}',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Signing failed: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _sendTransaction(BuildContext context) async {
    // Show transaction dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaction feature coming soon!'),
      ),
    );
  }
}

class _ChainSelector extends StatelessWidget {
  final ChainInfo selectedChain;
  final Function(ChainInfo) onChainSelected;

  const _ChainSelector({
    required this.selectedChain,
    required this.onChainSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showChainPicker(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.language,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedChain.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (selectedChain.isTestnet)
                            Text(
                              'Testnet',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orange,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChainPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _ChainSelectorSheet(
        onChainSelected: (chain) {
          Navigator.pop(context);
          onChainSelected(chain);
        },
      ),
    );
  }
}

class _ChainSelectorSheet extends ConsumerWidget {
  final Function(ChainInfo) onChainSelected;

  const _ChainSelectorSheet({
    required this.onChainSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chains = ref.watch(allChainsProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Network',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: chains.length,
              itemBuilder: (context, index) {
                final chain = chains[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(chain.symbol[0]),
                  ),
                  title: Text(chain.name),
                  subtitle: Text(chain.symbol),
                  trailing: chain.isTestnet
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Testnet',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.orange,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => onChainSelected(chain),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectWalletCard extends StatelessWidget {
  final VoidCallback onConnect;

  const _ConnectWalletCard({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Connect your wallet',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your crypto wallet to get started',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link),
              label: const Text('Connect Wallet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onSignMessage;
  final VoidCallback onSendTransaction;

  const _ActionButtons({
    required this.onSignMessage,
    required this.onSendTransaction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSignMessage,
                    icon: const Icon(Icons.edit),
                    label: const Text('Sign Message'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSendTransaction,
                    icon: const Icon(Icons.send),
                    label: const Text('Send TX'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Connection Error',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
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
