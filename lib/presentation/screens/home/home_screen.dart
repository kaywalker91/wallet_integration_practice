import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/chain_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/balance_provider.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/wallet_card.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/wallet_selector.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/connected_wallets_section.dart';
import 'package:wallet_integration_practice/presentation/widgets/common/loading_overlay.dart';

/// Main home screen
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isConnecting = false;

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
                      AppLogger.d('[DEBUG] HomeScreen: balanceAsync state = ${balanceAsync.isLoading ? "loading" : balanceAsync.hasError ? "error" : "data"}');

                      final balance = balanceAsync.whenOrNull(
                        data: (entity) {
                          AppLogger.d('[DEBUG] HomeScreen: balance entity = $entity');
                          return entity?.balanceFormatted;
                        },
                      );

                      return WalletCard(
                        wallet: wallet,
                        onDisconnect: () => _disconnectActiveWallet(activeEntry.id),
                        // Chain switching removed - wallet auto-connects to default chain
                        balance: balance,
                        tokenSymbol: tokenSymbol,
                        onSignMessage: () => _signMessage(context),
                        // onSendTransaction: null, // Disabled until implemented
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

                // 3. Network selector (secondary - can be changed after wallet connection)
                // _ChainSelector(
                //   selectedChain: selectedChain,
                //   onChainSelected: (chain) {
                //     ref.read(chainSelectionProvider.notifier).selectChain(chain);
                //   },
                // ),

                // QR Code is now shown as a modal, not inline
              ],
            ),
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
    setState(() {
      _isConnecting = true;
    });

    try {
      // Get default chain from wallet type (EVM priority: Ethereum Mainnet)
      final defaultChainId = wallet.type.defaultChainId;
      final defaultCluster = wallet.type.defaultCluster;

      // Update chainSelectionProvider for balance display consistency
      final chain = SupportedChains.getByChainId(defaultChainId);
      if (chain != null) {
        ref.read(chainSelectionProvider.notifier).selectChain(chain);
      }

      // Start connection - adapter will auto-launch wallet app via deep link
      // If wallet is not installed, adapter throws WalletNotInstalledException
      await ref.read(multiWalletNotifierProvider.notifier).connectWallet(
            walletType: wallet.type,
            chainId: defaultChainId,
            cluster: defaultCluster,
          );

      // Connection completion is handled by stream listener in provider

    } on WalletNotInstalledException catch (e) {
      // Wallet app is not installed - show install dialog
      AppLogger.w('Wallet not installed: ${e.walletType}');
      if (mounted) {
        final shouldInstall = await _showInstallDialog(wallet);
        if (shouldInstall && mounted) {
          await _openAppStore(wallet.type);
        }
      }
    } catch (e) {
      AppLogger.e('Connection error', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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

  /// Show dialog asking user to install wallet
  Future<bool> _showInstallDialog(WalletInfo wallet) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('${wallet.name} Not Installed'),
            content: Text(
              '${wallet.name} is not installed on this device.\n'
              'Would you like to install it from the app store?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Install'),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Open app store for wallet download
  Future<void> _openAppStore(WalletType type) async {
    final storeIds = {
      WalletType.metamask: (
        WalletConstants.metamaskAppStoreId,
        WalletConstants.metamaskPackageAndroid
      ),
      WalletType.trustWallet: (
        WalletConstants.trustWalletAppStoreId,
        WalletConstants.trustWalletPackageAndroid
      ),
      WalletType.phantom: (
        WalletConstants.phantomAppStoreId,
        WalletConstants.phantomPackageAndroid
      ),
      WalletType.rabby: (
        WalletConstants.rabbyAppStoreId,
        WalletConstants.rabbyPackageAndroid
      ),
    };

    final ids = storeIds[type];
    if (ids == null) return;

    final (appStoreId, packageName) = ids;

    String storeUrl;
    if (Platform.isIOS) {
      storeUrl = 'https://apps.apple.com/app/id$appStoreId';
    } else if (Platform.isAndroid) {
      storeUrl = 'https://play.google.com/store/apps/details?id=$packageName';
    } else {
      return;
    }

    try {
      await launchUrl(
        Uri.parse(storeUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      AppLogger.e('Error opening app store', e);
    }
  }

  Future<void> _disconnectActiveWallet(String walletId) async {
    await ref.read(multiWalletNotifierProvider.notifier).disconnectWallet(walletId);
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

// Reserved for future use: Error state card
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
