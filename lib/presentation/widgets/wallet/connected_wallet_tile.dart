import 'package:flutter/material.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';

/// A tile widget representing a single wallet in the connected wallets list.
///
/// Displays wallet icon, name, address, network, connected date, token value,
/// and provides copy/visibility toggle actions.
///
/// ## Verification Checklist:
/// 1. Multiple wallets display correctly with proper layout
/// 2. Copy button copies full wallet address to clipboard
/// 3. Show/Hide toggle properly masks/unmasks: address, network, date, token value
class ConnectedWalletTile extends StatefulWidget {
  final ConnectedWalletEntry entry;
  final VoidCallback? onMakeActive;
  final VoidCallback? onDisconnect;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  /// Optional balance value for display
  /// In production, this would come from blockchain data
  final double? balance;

  const ConnectedWalletTile({
    super.key,
    required this.entry,
    this.onMakeActive,
    this.onDisconnect,
    this.onRetry,
    this.onRemove,
    this.balance,
  });

  @override
  State<ConnectedWalletTile> createState() => _ConnectedWalletTileState();
}

class _ConnectedWalletTileState extends State<ConnectedWalletTile> {
  /// Controls visibility of sensitive information
  /// Default is true (Show state)
  bool _isInfoVisible = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = widget.entry.wallet;
    final isConnecting = widget.entry.status == WalletEntryStatus.connecting;
    final hasError = widget.entry.status == WalletEntryStatus.error;
    final isConnected = widget.entry.status == WalletEntryStatus.connected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasError
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.3)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: widget.entry.isActive
            ? Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
                width: 2,
              )
            : Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main content row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: Icon + Info
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wallet icon
                    _WalletIcon(walletType: wallet.type),
                    const SizedBox(width: 12),

                    // Wallet info column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Wallet name
                          Text(
                            '${wallet.type.displayName} Wallet',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),

                          // Address
                          Row(
                            children: [
                              Icon(
                                Icons.link,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  isConnecting
                                      ? 'Connecting...'
                                      : _isInfoVisible
                                          ? AddressUtils.truncate(wallet.address)
                                          : WalletUtils.maskText(wallet.address),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontFamily: 'monospace',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Network
                          Row(
                            children: [
                              Icon(
                                Icons.language,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _isInfoVisible
                                      ? WalletUtils.getNetworkName(
                                          wallet.chainId, wallet.cluster)
                                      : WalletUtils.maskText('network', length: 8),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Connected Date
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _isInfoVisible
                                      ? WalletUtils.formatConnectedDate(
                                          wallet.connectedAt)
                                      : WalletUtils.maskText('date', length: 8),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Right side: Balance + Actions
              // Constrained to prevent overflow on small screens
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Token Value
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _isInfoVisible
                            ? WalletUtils.formatTokenBalance(widget.balance)
                            : WalletUtils.maskBalance(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      'Balance',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Action icons row
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Show/Hide toggle
                        _ActionIconButton(
                          icon: _isInfoVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                          tooltip: _isInfoVisible
                              ? 'Hide wallet info'
                              : 'Show wallet info',
                          onPressed: _toggleVisibility,
                        ),

                        // Copy address button
                        _ActionIconButton(
                          icon: Icons.copy,
                          tooltip: 'Copy ${wallet.type.displayName} Wallet address',
                          onPressed: () => _copyAddress(context),
                        ),

                        // Delete/Remove button
                        if (widget.onRemove != null || widget.onDisconnect != null)
                          _ActionIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Remove wallet',
                            onPressed: () {
                              if (hasError && widget.onRemove != null) {
                                widget.onRemove!();
                              } else if (widget.onDisconnect != null) {
                                widget.onDisconnect!();
                              }
                            },
                            color: theme.colorScheme.error,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Active wallet badge
          if (widget.entry.isActive && isConnected) ...[
            const SizedBox(height: 8),
            const ActiveWalletBadge(),
          ],

          // Error message
          if (hasError && widget.entry.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.entry.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onRetry != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onRetry,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Make Active button for non-active connected wallets
          if (!widget.entry.isActive &&
              isConnected &&
              widget.onMakeActive != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onMakeActive,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('Make Active'),
              ),
            ),
          ],

          // Loading indicator for connecting state
          if (isConnecting) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  void _toggleVisibility() {
    setState(() {
      _isInfoVisible = !_isInfoVisible;
    });
  }

  Future<void> _copyAddress(BuildContext context) async {
    final address = widget.entry.wallet.address;
    final success = await WalletUtils.copyToClipboard(address);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Address copied to clipboard'
                : 'Failed to copy address',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Icon button for wallet tile actions
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: tooltip,
      button: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: color ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Wallet type icon with fallback
class _WalletIcon extends StatelessWidget {
  final WalletType walletType;

  const _WalletIcon({required this.walletType});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Try to load wallet icon asset, fallback to letter avatar
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        walletType.iconAsset,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to letter avatar
          final letter = walletType.displayName.isNotEmpty
              ? walletType.displayName[0].toUpperCase()
              : 'W';
          return Container(
            color: theme.colorScheme.primaryContainer,
            child: Center(
              child: Text(
                letter,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Badge indicating this is the active wallet
class ActiveWalletBadge extends StatelessWidget {
  const ActiveWalletBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            'Active Wallet',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
