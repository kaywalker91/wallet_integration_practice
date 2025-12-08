import 'package:flutter/material.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';

/// Bottom sheet for selecting a network before wallet connection.
/// Returns the selected [ChainInfo] or null if cancelled.
class SelectNetworkSheet extends StatefulWidget {
  const SelectNetworkSheet({super.key});

  /// Available network options for wallet connection.
  /// Only mainnet chains are shown as per requirements.
  static const List<ChainInfo> networkOptions = [
    SupportedChains.ilityMainnet,
    SupportedChains.ethereumMainnet,
    SupportedChains.baseMainnet,
    SupportedChains.bnbMainnet,
  ];

  /// Show network selector bottom sheet.
  /// Returns the selected [ChainInfo] or null if user cancels.
  static Future<ChainInfo?> show(BuildContext context) {
    return showModalBottomSheet<ChainInfo>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const SelectNetworkSheet(),
    );
  }

  @override
  State<SelectNetworkSheet> createState() => _SelectNetworkSheetState();
}

class _SelectNetworkSheetState extends State<SelectNetworkSheet> {
  // Default selection: Ethereum Mainnet
  ChainInfo _selectedChain = SupportedChains.ethereumMainnet;

  @override
  Widget build(BuildContext context) {
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
                'Select Network',
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
            'Choose a network for your wallet connection',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Network list
          ...SelectNetworkSheet.networkOptions.map(
            (chain) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _NetworkTile(
                chain: chain,
                isSelected: _selectedChain.chainId == chain.chainId,
                onTap: () {
                  setState(() {
                    _selectedChain = chain;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _selectedChain),
              child: const Text('Confirm'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Individual network tile with selection indicator.
class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.chain,
    required this.isSelected,
    required this.onTap,
  });

  final ChainInfo chain;
  final bool isSelected;
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
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Row(
          children: [
            // Chain icon (avatar with first letter of symbol)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getChainColor(chain.chainId).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  chain.symbol[0],
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _getChainColor(chain.chainId),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chain.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chain.symbol,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Selection indicator
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 24,
              )
            else
              Icon(
                Icons.radio_button_unchecked,
                color: theme.colorScheme.outline,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  /// Get chain-specific color for visual distinction.
  Color _getChainColor(int? chainId) {
    switch (chainId) {
      case ChainConstants.ethereumMainnet:
        return const Color(0xFF627EEA); // Ethereum blue
      case ChainConstants.baseMainnet:
        return const Color(0xFF0052FF); // Base blue
      case ChainConstants.bnbMainnet:
        return const Color(0xFFF0B90B); // BNB yellow
      case ChainConstants.ilityMainnet:
        return const Color(0xFF00C853); // ILITY green
      default:
        return Colors.grey;
    }
  }
}
