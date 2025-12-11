import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wallet_integration_practice/core/utils/address_utils.dart';
import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';

/// Hero-style card displaying connected wallet information with integrated actions
class WalletCard extends StatelessWidget {
  final WalletEntity wallet;
  final VoidCallback? onDisconnect;
  final VoidCallback? onSwitchChain;

  /// Optional balance to display (in native token)
  final double? balance;

  /// Symbol for the native token (e.g., 'ETH', 'SOL')
  final String? tokenSymbol;

  /// Callback for signing a message
  final VoidCallback? onSignMessage;

  /// Callback for sending a transaction (null = disabled/coming soon)
  final VoidCallback? onSendTransaction;

  const WalletCard({
    super.key,
    required this.wallet,
    this.onDisconnect,
    this.onSwitchChain,
    this.balance,
    this.tokenSymbol,
    this.onSignMessage,
    this.onSendTransaction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF1a1a2e),
                  const Color(0xFF16213e),
                  const Color(0xFF0f3460),
                ]
              : [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.85),
                  theme.colorScheme.secondary,
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background pattern
            Positioned(
              right: -50,
              top: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              left: -30,
              bottom: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  _buildHeader(context, theme),

                  const SizedBox(height: 24),

                  // Balance section
                  _buildBalanceSection(context, theme),

                  const SizedBox(height: 24),

                  // Address section
                  _buildAddressSection(context, theme),

                  // Chain info
                  if (wallet.chainId != null || wallet.cluster != null) ...[
                    const SizedBox(height: 16),
                    _buildChainInfo(context, theme),
                  ],

                  // Quick Actions
                  if (onSignMessage != null) ...[
                    const SizedBox(height: 20),
                    _buildQuickActions(context, theme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        // Wallet icon
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            wallet.type.iconAsset,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wallet.walletName,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Connected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Disconnect button
        if (onDisconnect != null)
          IconButton(
            onPressed: onDisconnect,
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            tooltip: 'Options',
          ),
      ],
    );
  }

  Widget _buildBalanceSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Balance',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white60,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        balance != null
            ? _AnimatedBalanceText(
                value: balance!,
                tokenSymbol: tokenSymbol,
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
                symbolStyle: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              )
            : Text(
                '---',
                style: theme.textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1,
                ),
              ),
      ],
    );
  }

  Widget _buildAddressSection(BuildContext context, ThemeData theme) {
    return InkWell(
      onTap: () => _copyAddress(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                AddressUtils.truncate(wallet.address, start: 8, end: 6),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Icon(
              Icons.copy_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChainInfo(BuildContext context, ThemeData theme) {
    final chainText = wallet.chainId != null
        ? 'Chain ID: ${wallet.chainId}'
        : 'Cluster: ${wallet.cluster}';

    return Row(
      children: [
        Icon(
          Icons.language,
          size: 16,
          color: Colors.white.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Text(
          chainText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const Spacer(),
        if (onSwitchChain != null)
          TextButton(
            onPressed: onSwitchChain,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Switch'),
                SizedBox(width: 4),
                Icon(Icons.swap_horiz, size: 16),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.edit_note,
            label: 'Sign',
            onPressed: onSignMessage,
            isPrimary: false,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.send,
            label: 'Send',
            onPressed: onSendTransaction,
            isPrimary: true,
            isDisabled: onSendTransaction == null,
          ),
        ),
      ],
    );
  }

  Future<void> _copyAddress(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: wallet.address));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Address copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  String _formatBalance(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    } else if (value >= 1) {
      return value.toStringAsFixed(4);
    } else {
      return value.toStringAsFixed(6);
    }
  }
}

class _AnimatedBalanceText extends StatelessWidget {
  final double value;
  final String? tokenSymbol;
  final TextStyle? style;
  final TextStyle? symbolStyle;

  const _AnimatedBalanceText({
    required this.value,
    this.tokenSymbol,
    this.style,
    this.symbolStyle,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 2000),
      curve: Curves.easeOutExpo,
      builder: (context, val, child) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _format(val),
              style: style,
            ),
            if (tokenSymbol != null) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tokenSymbol!,
                    style: symbolStyle,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  String _format(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(2)}K';
    } else if (value >= 1) {
      return value.toStringAsFixed(4);
    } else {
      return value.toStringAsFixed(6);
    }
  }
}

/// Action button for wallet card
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDisabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.isPrimary = false,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isDisabled ? null : onPressed;

    return Tooltip(
      message: isDisabled ? 'Coming soon' : '',
      child: Material(
        color: isPrimary
            ? Colors.white.withValues(alpha: isDisabled ? 0.1 : 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: effectiveOnPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isPrimary
                  ? null
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: Colors.white.withValues(alpha: isDisabled ? 0.4 : 0.9),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: isDisabled ? 0.4 : 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
