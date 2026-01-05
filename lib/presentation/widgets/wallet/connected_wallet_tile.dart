import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/balance_provider.dart';

/// A compact tile widget representing a single wallet in the connected wallets list.
///
/// Simplified design showing essential information with expandable details.
class ConnectedWalletTile extends StatefulWidget {
  const ConnectedWalletTile({
    super.key,
    required this.entry,
    this.onMakeActive,
    this.onDisconnect,
    this.onRetry,
    this.onRemove,
    this.onReconnect,
    this.balance,
  });

  final ConnectedWalletEntry entry;
  final VoidCallback? onMakeActive;
  final VoidCallback? onDisconnect;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  /// Callback when user wants to reconnect a stale session
  final VoidCallback? onReconnect;

  /// Optional balance value for display
  final double? balance;

  @override
  State<ConnectedWalletTile> createState() => _ConnectedWalletTileState();
}

class _ConnectedWalletTileState extends State<ConnectedWalletTile>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    // Start shimmer animation if connecting
    if (widget.entry.status == WalletEntryStatus.connecting) {
      _shimmerController.repeat();
    }
  }

  @override
  void didUpdateWidget(ConnectedWalletTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle status changes
    if (widget.entry.status == WalletEntryStatus.connecting) {
      if (!_shimmerController.isAnimating) {
        _shimmerController.repeat();
      }
    } else {
      _shimmerController.stop();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallet = widget.entry.wallet;
    final isConnecting = widget.entry.status == WalletEntryStatus.connecting;
    final hasError = widget.entry.status == WalletEntryStatus.error;
    final isConnected = widget.entry.status == WalletEntryStatus.connected;
    final isStale = wallet.isStale;

    // Wrap with shimmer effect for connecting state
    final Widget tileContent = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _getBackgroundColor(theme, hasError: hasError, isStale: isStale),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getBorderColor(theme, hasError: hasError, isStale: isStale),
          width: widget.entry.isActive ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isConnected && !widget.entry.isActive && widget.onMakeActive != null
              ? widget.onMakeActive
              : () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Main row - always visible
                _buildMainRow(theme, wallet, isConnecting, hasError, isConnected, isStale),

                // Loading indicator
                if (isConnecting) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(),
                ],

                // Stale session section
                if (isStale && !hasError) ...[
                  const SizedBox(height: 8),
                  _buildStaleSection(theme),
                ],

                // Error section
                if (hasError && widget.entry.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  _buildErrorSection(theme),
                ],

                // Expanded details
                if (_isExpanded && !hasError && !isStale) ...[
                  const SizedBox(height: 12),
                  _buildExpandedDetails(theme, wallet, isConnected),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // Apply shimmer overlay for connecting state
    if (isConnecting) {
      return AnimatedBuilder(
        animation: _shimmerAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ShaderMask(
                    shaderCallback: (bounds) {
                      return LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.transparent,
                          theme.colorScheme.primary.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                        stops: [
                          _shimmerAnimation.value - 0.3,
                          _shimmerAnimation.value,
                          _shimmerAnimation.value + 0.3,
                        ].map((s) => s.clamp(0.0, 1.0)).toList(),
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.srcATop,
                    child: Container(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: tileContent,
      );
    }

    return tileContent;
  }

  Color _getBackgroundColor(ThemeData theme, {required bool hasError, bool isStale = false}) {
    if (hasError) {
      return theme.colorScheme.errorContainer.withValues(alpha: 0.2);
    }
    if (isStale) {
      return Colors.orange.withValues(alpha: 0.08);
    }
    if (widget.entry.isActive) {
      return theme.colorScheme.primaryContainer.withValues(alpha: 0.15);
    }
    return theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
  }

  Color _getBorderColor(ThemeData theme, {required bool hasError, bool isStale = false}) {
    if (hasError) {
      return theme.colorScheme.error.withValues(alpha: 0.3);
    }
    if (isStale) {
      return Colors.orange.withValues(alpha: 0.4);
    }
    if (widget.entry.isActive) {
      return theme.colorScheme.primary.withValues(alpha: 0.5);
    }
    return theme.colorScheme.outline.withValues(alpha: 0.15);
  }

  Widget _buildMainRow(
    ThemeData theme,
    WalletEntity wallet,
    bool isConnecting,
    bool hasError,
    bool isConnected,
    bool isStale,
  ) {
    return Row(
      children: [
        // Wallet icon
        _WalletIcon(
          walletType: wallet.type,
          isActive: widget.entry.isActive,
          hasError: hasError,
          isConnecting: isConnecting,
          isStale: isStale,
        ),
        const SizedBox(width: 12),

        // Wallet info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      wallet.type.displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isStale ? theme.colorScheme.onSurfaceVariant : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.entry.isActive && isConnected && !isStale)
                    _ActiveBadge(theme: theme),
                  if (isStale)
                    _StaleBadge(theme: theme),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                isConnecting
                    ? 'Connecting...'
                    : isStale
                        ? '${AddressUtils.truncate(wallet.address, start: 6, end: 4)} · 재연결 필요'
                        : '${AddressUtils.truncate(wallet.address, start: 6, end: 4)} · ${WalletUtils.getNetworkName(wallet.chainId, wallet.cluster)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isStale ? Colors.orange : theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Balance
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatBalance(widget.balance),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              _isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStaleSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.sync_problem,
            size: 16,
            color: Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '세션이 만료되었습니다. 다시 연결해주세요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade800,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.onReconnect != null) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.onReconnect,
              icon: const Icon(Icons.refresh, size: 14),
              label: const Text('재연결'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: const Size(0, 28),
                textStyle: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 28),
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedDetails(
    ThemeData theme,
    WalletEntity wallet,
    bool isConnected,
  ) {
    return Column(
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),

        // Details grid
        Row(
          children: [
            Expanded(
              child: _DetailItem(
                icon: Icons.language,
                label: 'Network',
                value: WalletUtils.getNetworkName(wallet.chainId, wallet.cluster),
                theme: theme,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _DetailItem(
                icon: Icons.schedule,
                label: 'Connected',
                value: WalletUtils.formatConnectedDate(wallet.connectedAt),
                theme: theme,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Action buttons
        Row(
          children: [
            // Copy address
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copyAddress(context),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  textStyle: theme.textTheme.labelMedium,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Make active (if not active)
            if (!widget.entry.isActive && isConnected && widget.onMakeActive != null)
              Expanded(
                child: FilledButton.icon(
                  onPressed: widget.onMakeActive,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Use'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                ),
              ),

            // Disconnect/Remove
            if (widget.onDisconnect != null || widget.onRemove != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.entry.status == WalletEntryStatus.error
                    ? widget.onRemove
                    : widget.onDisconnect,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
                tooltip: 'Remove wallet',
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.error.withValues(alpha: 0.1),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _copyAddress(BuildContext context) async {
    final address = widget.entry.wallet.address;
    final success = await WalletUtils.copyToClipboard(address);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Address copied' : 'Failed to copy',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  String _formatBalance(double? balance) {
    if (balance == null) return '---';
    if (balance >= 1000000) {
      return '\$${(balance / 1000000).toStringAsFixed(2)}M';
    } else if (balance >= 1000) {
      return '\$${(balance / 1000).toStringAsFixed(2)}K';
    } else {
      return '\$${balance.toStringAsFixed(2)}';
    }
  }
}

/// Compact wallet icon with status indicator and pulse animation
class _WalletIcon extends StatefulWidget {
  const _WalletIcon({
    required this.walletType,
    required this.isActive,
    required this.hasError,
    this.isConnecting = false,
    this.isStale = false,
  });

  final WalletType walletType;
  final bool isActive;
  final bool hasError;
  final bool isConnecting;
  final bool isStale;

  @override
  State<_WalletIcon> createState() => _WalletIconState();
}

class _WalletIconState extends State<_WalletIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start pulse animation if active (but not stale)
    if (widget.isActive && !widget.hasError && !widget.isStale) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_WalletIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !widget.hasError && !widget.isStale) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            widget.walletType.iconAsset,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return ColoredBox(
                color: theme.colorScheme.primaryContainer,
                child: Center(
                  child: Text(
                    widget.walletType.displayName[0].toUpperCase(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Connecting spinner
        if (widget.isConnecting)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 18,
              height: 18,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            ),
          )
        // Status indicator with pulse
        else
          Positioned(
            right: -2,
            bottom: -2,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                final scale = widget.isActive && !widget.hasError && !widget.isStale
                    ? _pulseAnimation.value
                    : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: widget.hasError
                          ? Colors.red
                          : widget.isStale
                              ? Colors.orange
                              : widget.isActive
                                  ? Colors.green
                                  : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                      boxShadow: widget.isActive && !widget.hasError && !widget.isStale
                          ? [
                              BoxShadow(
                                color: Colors.green.withValues(
                                  alpha: 0.4 * (scale - 1.0) / 0.3,
                                ),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: widget.hasError
                        ? const Icon(Icons.close, size: 8, color: Colors.white)
                        : widget.isStale
                            ? const Icon(Icons.sync_problem, size: 8, color: Colors.white)
                            : widget.isActive
                                ? const Icon(Icons.check, size: 8, color: Colors.white)
                                : null,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Active badge indicator
class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Active',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}

/// Stale badge indicator for sessions that need reconnection
class _StaleBadge extends StatelessWidget {
  const _StaleBadge({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.sync_problem,
            size: 10,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            'Stale',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail item widget for expanded view
class _DetailItem extends StatelessWidget {
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Auto-Balance Wrapper
// ============================================================================

/// A wrapper widget that automatically fetches balance for a ConnectedWalletTile.
///
/// Use this instead of [ConnectedWalletTile] when you want automatic
/// balance fetching based on the wallet's chain.
class ConnectedWalletTileWithBalance extends ConsumerWidget {
  const ConnectedWalletTileWithBalance({
    super.key,
    required this.entry,
    this.onMakeActive,
    this.onDisconnect,
    this.onRetry,
    this.onRemove,
    this.onReconnect,
  });

  final ConnectedWalletEntry entry;
  final VoidCallback? onMakeActive;
  final VoidCallback? onDisconnect;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Determine the chain for this wallet
    final wallet = entry.wallet;
    ChainInfo? chain;

    if (wallet.chainId != null) {
      chain = SupportedChains.getByChainId(wallet.chainId!);
    } else if (wallet.cluster != null) {
      chain = SupportedChains.solanaChains
          .where((c) => c.cluster == wallet.cluster)
          .firstOrNull;
    }

    // Fetch balance if chain is known
    double? balance;
    if (chain != null && entry.status == WalletEntryStatus.connected) {
      final balanceAsync = ref.watch(chainBalanceProvider(chain));
      balance = balanceAsync.when(
        data: (b) => b?.balanceFormatted,
        loading: () => null,
        error: (_, _) => null,
      );
    }

    return ConnectedWalletTile(
      entry: entry,
      balance: balance,
      onMakeActive: onMakeActive,
      onDisconnect: onDisconnect,
      onRetry: onRetry,
      onRemove: onRemove,
      onReconnect: onReconnect,
    );
  }
}
