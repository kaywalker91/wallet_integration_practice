import 'package:flutter/material.dart';
import 'package:wallet_integration_practice/presentation/widgets/common/shimmer.dart';

/// Skeleton placeholder for ConnectedWalletsSection during loading/restoration.
///
/// Displays shimmer placeholders matching the connected wallets section layout.
class ConnectedWalletsSkeleton extends StatelessWidget {
  const ConnectedWalletsSkeleton({
    super.key,
    this.itemCount = 2,
  });

  /// Number of wallet tile skeletons to show
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header skeleton
            _buildHeaderSkeleton(context),

            const SizedBox(height: 16),

            // Wallet tiles skeleton
            ...List.generate(itemCount, (index) {
              return Column(
                children: [
                  const _WalletTileSkeleton(),
                  if (index < itemCount - 1) const SizedBox(height: 12),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Title with icon placeholder
        Row(
          children: [
            ShimmerIcon(
              size: 20,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(width: 8),
            const ShimmerText(width: 130, height: 18),
            const SizedBox(width: 8),
            ShimmerBox(
              width: 24,
              height: 20,
              borderRadius: BorderRadius.circular(10),
            ),
          ],
        ),

        // Add Wallet button skeleton
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShimmerBox(
                width: 18,
                height: 18,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 6),
              const ShimmerText(width: 70, height: 14),
            ],
          ),
        ),
      ],
    );
  }
}

/// Skeleton placeholder for a single connected wallet tile.
///
/// Matches the ConnectedWalletTile layout with shimmer placeholders.
class _WalletTileSkeleton extends StatelessWidget {
  const _WalletTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          // Wallet icon skeleton
          _buildWalletIconSkeleton(context),
          const SizedBox(width: 12),

          // Wallet info skeleton
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerText(width: 90, height: 16),
                SizedBox(height: 4),
                ShimmerText(width: 150, height: 12),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Balance skeleton
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShimmerText(width: 60, height: 16),
              SizedBox(height: 4),
              ShimmerIcon(
                size: 18,
                borderRadius: BorderRadius.all(Radius.circular(4)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWalletIconSkeleton(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main icon
        ShimmerBox(
          width: 40,
          height: 40,
          borderRadius: BorderRadius.circular(10),
        ),
        // Status indicator
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.surface,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone skeleton for a single wallet tile (can be used independently).
class ConnectedWalletTileSkeleton extends StatelessWidget {
  const ConnectedWalletTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WalletTileSkeleton();
  }
}
