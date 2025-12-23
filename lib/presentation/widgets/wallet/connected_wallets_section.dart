import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/widgets/wallet/connected_wallet_tile.dart';

/// Section widget displaying the list of all connected wallets.
///
/// Shows each wallet's status and provides actions for managing connections.
/// Includes "+ Add Wallet" button in the header for adding new wallets.
///
/// ## Verification Checklist:
/// 1. Multiple wallets display with correct card layout
/// 2. "+ Add Wallet" button is visible in header and triggers wallet selection
/// 3. Empty state shows appropriate message and connect button
class ConnectedWalletsSection extends ConsumerWidget {
  const ConnectedWalletsSection({
    super.key,
    required this.onConnectAnother,
  });

  final VoidCallback onConnectAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final multiWalletState = ref.watch(multiWalletNotifierProvider);
    final wallets = multiWalletState.wallets;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with title and Add Wallet button
            _SectionHeader(
              walletCount: multiWalletState.connectedCount,
              onAddWallet: onConnectAnother,
            ),

            const SizedBox(height: 16),

            // Wallet list or empty state
            if (wallets.isEmpty)
              _EmptyState(onConnect: onConnectAnother)
            else
              _WalletList(
                wallets: wallets,
                onMakeActive: (id) {
                  ref.read(multiWalletNotifierProvider.notifier).setActiveWallet(id);
                },
                onDisconnect: (id) {
                  ref.read(multiWalletNotifierProvider.notifier).disconnectWallet(id);
                },
                onRetry: (id) {
                  ref.read(multiWalletNotifierProvider.notifier).reconnectWallet(id);
                },
                onRemove: (id) {
                  ref.read(multiWalletNotifierProvider.notifier).removeWallet(id);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Section header with title and Add Wallet button
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.walletCount,
    required this.onAddWallet,
  });

  final int walletCount;
  final VoidCallback onAddWallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title with link icon
        Row(
          children: [
            Icon(
              Icons.link,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'Connected Wallets',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (walletCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$walletCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),

        // Add Wallet button - styled as outlined button with icon
        OutlinedButton.icon(
          onPressed: onAddWallet,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Wallet'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 36),
            textStyle: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No wallets connected',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Connect a wallet to get started',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Connect Wallet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletList extends StatelessWidget {
  const _WalletList({
    required this.wallets,
    required this.onMakeActive,
    required this.onDisconnect,
    required this.onRetry,
    required this.onRemove,
  });

  final List wallets;
  final Function(String) onMakeActive;
  final Function(String) onDisconnect;
  final Function(String) onRetry;
  final Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: wallets.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = wallets[index];

        // Use ConnectedWalletTileWithBalance for automatic balance fetching
        return ConnectedWalletTileWithBalance(
          entry: entry,
          onMakeActive: () => onMakeActive(entry.id),
          onDisconnect: () => onDisconnect(entry.id),
          onRetry: () => onRetry(entry.id),
          onRemove: () => onRemove(entry.id),
        );
      },
    );
  }
}
