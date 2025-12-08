import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/domain/entities/session_account.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';

/// Dialog for selecting the active account from multiple session accounts.
///
/// Displays all accounts approved by the wallet and allows the user
/// to select which account to use for transactions.
class AccountSelectorDialog extends ConsumerWidget {
  const AccountSelectorDialog({super.key});

  /// Show the account selector dialog.
  ///
  /// Returns the selected address, or null if cancelled.
  static Future<String?> show(BuildContext context) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AccountSelectorDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(sessionAccountsListProvider);
    final activeAddress = ref.watch(activeAccountAddressProvider);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Account',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${accounts.length} accounts connected',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Account list
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: accounts.length,
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  final isActive = account.address.toLowerCase() ==
                      activeAddress?.toLowerCase();

                  return _AccountTile(
                    account: account,
                    isActive: isActive,
                    onTap: () {
                      ref
                          .read(activeAccountNotifierProvider.notifier)
                          .setActiveAccount(account.address);
                      Navigator.of(context).pop(account.address);
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final SessionAccount account;
  final bool isActive;
  final VoidCallback onTap;

  const _AccountTile({
    required this.account,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive
              ? theme.primaryColor.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(color: theme.primaryColor, width: 2)
              : null,
        ),
        child: Center(
          child: Text(
            _getAccountEmoji(account),
            style: const TextStyle(fontSize: 24),
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              account.displayName ?? 'Account ${account.shortAddress}',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Active',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  account.shortAddress,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: account.address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Address copied'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _ChainBadge(chainId: account.chainId),
        ],
      ),
      trailing: isActive
          ? Icon(Icons.check_circle, color: theme.primaryColor)
          : const Icon(Icons.chevron_right, color: Colors.grey),
    );
  }

  String _getAccountEmoji(SessionAccount account) {
    // Generate a consistent emoji based on address
    final emojis = ['🦊', '🐻', '🐼', '🐨', '🦁', '🐯', '🐸', '🐵'];
    final index = account.address.hashCode.abs() % emojis.length;
    return emojis[index];
  }
}

class _ChainBadge extends StatelessWidget {
  final String chainId;

  const _ChainBadge({required this.chainId});

  @override
  Widget build(BuildContext context) {
    final chainInfo = _getChainInfo(chainId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: chainInfo.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chainInfo.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: chainInfo.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            chainInfo.name,
            style: TextStyle(
              fontSize: 10,
              color: chainInfo.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  _ChainInfo _getChainInfo(String chainId) {
    switch (chainId) {
      case '1':
        return _ChainInfo('Ethereum', Colors.blue[700]!);
      case '137':
        return _ChainInfo('Polygon', Colors.purple[600]!);
      case '56':
        return _ChainInfo('BNB Chain', Colors.yellow[700]!);
      case '42161':
        return _ChainInfo('Arbitrum', Colors.blue[400]!);
      case '10':
        return _ChainInfo('Optimism', Colors.red[500]!);
      case '8453':
        return _ChainInfo('Base', Colors.blue[600]!);
      case '43114':
        return _ChainInfo('Avalanche', Colors.red[700]!);
      default:
        return _ChainInfo('Chain $chainId', Colors.grey);
    }
  }
}

class _ChainInfo {
  final String name;
  final Color color;

  _ChainInfo(this.name, this.color);
}

/// Compact account selector button for app bars or headers.
///
/// Shows the current active account and opens the selector dialog when tapped.
class AccountSelectorButton extends ConsumerWidget {
  const AccountSelectorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shouldShow = ref.watch(shouldShowAccountSelectorProvider);
    final activeAccount = ref.watch(activeSessionAccountProvider);

    if (!shouldShow || activeAccount == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: () => AccountSelectorDialog.show(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_circle_outlined,
              size: 20,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 8),
            Text(
              activeAccount.shortAddress,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              size: 16,
              color: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge showing the number of connected accounts.
///
/// Useful for indicating multiple accounts are available.
class MultiAccountBadge extends ConsumerWidget {
  const MultiAccountBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(sessionAccountsListProvider);
    final shouldShow = ref.watch(shouldShowAccountSelectorProvider);

    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${accounts.length}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
