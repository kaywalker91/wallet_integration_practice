import 'package:flutter/material.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';

/// Widget displaying the connection status of a wallet.
///
/// Shows a colored dot with status text based on [WalletEntryStatus].
class WalletStatusIndicator extends StatelessWidget {
  const WalletStatusIndicator({
    super.key,
    required this.status,
    this.showText = true,
    this.compact = false,
  });

  final WalletEntryStatus status;
  final bool showText;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getStatusColor();
    final text = status.displayName;

    if (compact) {
      return _buildDot(color);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == WalletEntryStatus.connecting)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            _buildDot(color),
          if (showText) ...[
            const SizedBox(width: 4),
            Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case WalletEntryStatus.connected:
        return Colors.green;
      case WalletEntryStatus.connecting:
        return Colors.blue;
      case WalletEntryStatus.disconnected:
        return Colors.grey;
      case WalletEntryStatus.error:
        return Colors.red;
    }
  }
}

/// Badge indicating the active wallet
class ActiveWalletBadge extends StatelessWidget {
  const ActiveWalletBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
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
            'Active',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
