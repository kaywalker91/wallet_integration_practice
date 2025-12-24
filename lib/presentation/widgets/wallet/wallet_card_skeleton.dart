import 'package:flutter/material.dart';
import 'package:wallet_integration_practice/presentation/widgets/common/shimmer.dart';

/// Skeleton placeholder for WalletCard during loading/restoration.
///
/// Mirrors the WalletCard layout with shimmer placeholders for all content areas.
class WalletCardSkeleton extends StatelessWidget {
  const WalletCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DecoratedBox(
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
                  theme.colorScheme.primary.withValues(alpha: 0.7),
                  theme.colorScheme.primary.withValues(alpha: 0.6),
                  theme.colorScheme.secondary.withValues(alpha: 0.7),
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background pattern (same as WalletCard)
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

            // Content skeleton
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row skeleton
                  _buildHeaderSkeleton(),

                  const SizedBox(height: 24),

                  // Balance section skeleton
                  _buildBalanceSectionSkeleton(),

                  const SizedBox(height: 24),

                  // Address section skeleton
                  _buildAddressSectionSkeleton(),

                  const SizedBox(height: 16),

                  // Chain info skeleton
                  _buildChainInfoSkeleton(),

                  const SizedBox(height: 20),

                  // Quick actions skeleton
                  _buildQuickActionsSkeleton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderSkeleton() {
    return Row(
      children: [
        // Wallet icon placeholder
        ShimmerBox(
          width: 44,
          height: 44,
          borderRadius: BorderRadius.circular(12),
          baseColor: Colors.white.withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wallet name placeholder
              ShimmerBox(
                width: 100,
                height: 18,
                borderRadius: BorderRadius.circular(4),
                baseColor: Colors.white.withValues(alpha: 0.15),
                highlightColor: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 6),
              // Status placeholder
              Row(
                children: [
                  ShimmerBox(
                    width: 8,
                    height: 8,
                    borderRadius: BorderRadius.circular(4),
                    baseColor: Colors.white.withValues(alpha: 0.15),
                    highlightColor: Colors.white.withValues(alpha: 0.25),
                  ),
                  const SizedBox(width: 6),
                  ShimmerBox(
                    width: 60,
                    height: 12,
                    borderRadius: BorderRadius.circular(4),
                    baseColor: Colors.white.withValues(alpha: 0.15),
                    highlightColor: Colors.white.withValues(alpha: 0.25),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Options button placeholder
        ShimmerBox(
          width: 40,
          height: 40,
          borderRadius: BorderRadius.circular(20),
          baseColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.2),
        ),
      ],
    );
  }

  Widget _buildBalanceSectionSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Balance" label placeholder
        ShimmerBox(
          width: 50,
          height: 12,
          borderRadius: BorderRadius.circular(4),
          baseColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 8),
        // Balance value placeholder
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ShimmerBox(
              width: 120,
              height: 36,
              borderRadius: BorderRadius.circular(6),
              baseColor: Colors.white.withValues(alpha: 0.15),
              highlightColor: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(width: 8),
            // Token symbol placeholder
            ShimmerBox(
              width: 50,
              height: 24,
              borderRadius: BorderRadius.circular(12),
              baseColor: Colors.white.withValues(alpha: 0.1),
              highlightColor: Colors.white.withValues(alpha: 0.2),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAddressSectionSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: ShimmerBox(
              height: 16,
              borderRadius: BorderRadius.circular(4),
              baseColor: Colors.white.withValues(alpha: 0.1),
              highlightColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(width: 8),
          ShimmerBox(
            width: 18,
            height: 18,
            borderRadius: BorderRadius.circular(4),
            baseColor: Colors.white.withValues(alpha: 0.1),
            highlightColor: Colors.white.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildChainInfoSkeleton() {
    return Row(
      children: [
        ShimmerBox(
          width: 16,
          height: 16,
          borderRadius: BorderRadius.circular(4),
          baseColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.2),
        ),
        const SizedBox(width: 6),
        ShimmerBox(
          width: 80,
          height: 12,
          borderRadius: BorderRadius.circular(4),
          baseColor: Colors.white.withValues(alpha: 0.1),
          highlightColor: Colors.white.withValues(alpha: 0.2),
        ),
      ],
    );
  }

  Widget _buildQuickActionsSkeleton() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: ShimmerBox(
                width: 60,
                height: 16,
                borderRadius: BorderRadius.circular(4),
                baseColor: Colors.white.withValues(alpha: 0.1),
                highlightColor: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: ShimmerBox(
                width: 60,
                height: 16,
                borderRadius: BorderRadius.circular(4),
                baseColor: Colors.white.withValues(alpha: 0.15),
                highlightColor: Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
