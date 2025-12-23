import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';

/// Bottom sheet for selecting a wallet to connect
class WalletSelector extends ConsumerWidget {
  const WalletSelector({
    super.key,
    required this.onWalletSelected,
  });

  final Function(WalletInfo) onWalletSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(supportedWalletsProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Connect Wallet',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select a wallet to connect',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Wallet list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: wallets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final wallet = wallets[index];
                return _WalletListTile(
                  wallet: wallet,
                  onTap: () {
                    Navigator.pop(context);
                    onWalletSelected(wallet);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Footer
          Center(
            child: Text(
              'By connecting, you agree to our Terms of Service',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show wallet selector bottom sheet
  static Future<void> show(
    BuildContext context, {
    required Function(WalletInfo) onWalletSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return WalletSelector(onWalletSelected: onWalletSelected);
        },
      ),
    );
  }
}

class _WalletListTile extends StatelessWidget {
  const _WalletListTile({
    required this.wallet,
    required this.onTap,
  });

  final WalletInfo wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Wallet icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: wallet.iconUrl.startsWith('assets/')
                  ? Image.asset(
                      wallet.iconUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.account_balance_wallet,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: wallet.iconUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Icon(
                        Icons.account_balance_wallet,
                        color: theme.colorScheme.primary,
                      ),
                      errorWidget: (context, url, error) => Icon(
                        Icons.account_balance_wallet,
                        color: theme.colorScheme.primary,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallet.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    wallet.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Chain support badges
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wallet.supportsEvm)
                  const _ChainBadge(label: 'EVM', color: Colors.blue),
                if (wallet.supportsSolana) ...[
                  const SizedBox(width: 4),
                  const _ChainBadge(label: 'SOL', color: Colors.purple),
                ],
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChainBadge extends StatelessWidget {
  const _ChainBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
