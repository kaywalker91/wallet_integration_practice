import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/constants/chain_constants.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';
import 'package:wallet_integration_practice/domain/entities/balance_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/balance_provider.dart';

/// A compact balance display widget showing the current chain balance
class BalanceDisplay extends ConsumerWidget {
  const BalanceDisplay({
    super.key,
    this.showRefreshButton = true,
    this.textStyle,
    this.padding,
  });

  final bool showRefreshButton;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(currentChainBalanceProvider);

    AppLogger.d('[DEBUG] BalanceDisplay.build - balanceAsync state: ${balanceAsync.isLoading ? "loading" : balanceAsync.hasError ? "error" : "data"}');

    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: balanceAsync.when(
        data: (balance) {
          AppLogger.d('[DEBUG] BalanceDisplay: received data - balance: $balance');
          return _buildBalanceContent(
            context,
            ref,
            theme,
            balance,
          );
        },
        loading: () {
          AppLogger.d('[DEBUG] BalanceDisplay: loading state');
          return _buildLoadingState(theme);
        },
        error: (error, _) {
          AppLogger.e('[DEBUG] BalanceDisplay: error state - $error');
          return _buildErrorState(theme, error.toString());
        },
      ),
    );
  }

  Widget _buildBalanceContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    NativeBalanceEntity? balance,
  ) {
    if (balance == null) {
      return Text(
        '---',
        style: textStyle ?? theme.textTheme.titleMedium,
      );
    }

    final formattedBalance = ref.watch(formattedBalanceProvider(balance));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formattedBalance,
          style: textStyle ??
              theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (showRefreshButton) ...[
          const SizedBox(width: 8),
          _RefreshButton(
            onPressed: () => ref.invalidate(currentChainBalanceProvider),
            isStale: balance.isStale,
          ),
        ],
      ],
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Loading...',
          style: textStyle ??
              theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme, String error) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 16,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: 4),
        Text(
          'Error',
          style: textStyle ??
              theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
        ),
      ],
    );
  }
}

/// Refresh button with stale indicator
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({
    required this.onPressed,
    required this.isStale,
  });

  final VoidCallback onPressed;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(
            Icons.refresh,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          if (isStale)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      tooltip: isStale ? 'Refresh (stale data)' : 'Refresh balance',
    );
  }
}

/// A card widget showing native balance for a specific chain
class ChainBalanceCard extends ConsumerWidget {
  const ChainBalanceCard({
    super.key,
    required this.chain,
    this.onTap,
  });

  final ChainInfo chain;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(chainBalanceProvider(chain));

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: balanceAsync.when(
            data: (balance) => _buildContent(context, ref, theme, balance),
            loading: () => _buildLoadingContent(theme),
            error: (error, _) => _buildErrorContent(theme, error.toString()),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    NativeBalanceEntity? balance,
  ) {
    final formattedBalance = balance != null
        ? ref.watch(formattedBalanceProvider(balance))
        : '0 ${chain.symbol}';

    return Row(
      children: [
        // Chain icon placeholder
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              chain.symbol.substring(0, chain.symbol.length > 2 ? 2 : chain.symbol.length),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Chain info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chain.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                chain.isTestnet ? 'Testnet' : 'Mainnet',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Balance
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedBalance,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (balance?.hasError ?? false)
              Text(
                'Error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLoadingContent(ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chain.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 60,
                height: 12,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent(ThemeData theme, String error) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                chain.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Failed to load',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A list widget showing balances across multiple chains
class MultiChainBalanceList extends ConsumerWidget {
  const MultiChainBalanceList({
    super.key,
    required this.chains,
    this.onChainTap,
    this.showLoading = true,
  });

  final List<ChainInfo> chains;
  final void Function(ChainInfo chain)? onChainTap;
  final bool showLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chains.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final chain = chains[index];
        return ChainBalanceCard(
          chain: chain,
          onTap: onChainTap != null ? () => onChainTap!(chain) : null,
        );
      },
    );
  }
}

/// A summary widget showing total balance across all chains
class TotalBalanceSummary extends ConsumerWidget {
  const TotalBalanceSummary({
    super.key,
    this.titleStyle,
    this.subtitleStyle,
  });

  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final aggregatedAsync = ref.watch(aggregatedBalancesProvider);

    return aggregatedAsync.when(
      data: (aggregated) {
        if (aggregated == null) {
          return _buildEmptyState(theme);
        }
        return _buildContent(theme, aggregated);
      },
      loading: () => _buildLoadingState(theme),
      error: (error, _) => _buildErrorState(theme),
    );
  }

  Widget _buildContent(ThemeData theme, AggregatedBalanceEntity aggregated) {
    final chainCount = aggregated.nativeBalances.length;
    final tokenCount = aggregated.tokenBalances.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Portfolio',
          style: subtitleStyle ??
              theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '$chainCount chains',
              style: titleStyle ??
                  theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (tokenCount > 0) ...[
              Text(
                ' · $tokenCount tokens',
                style: titleStyle ??
                    theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Text(
      'No balances',
      style: titleStyle ??
          theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Loading balances...',
          style: titleStyle ??
              theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Row(
      children: [
        Icon(
          Icons.error_outline,
          size: 16,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: 8),
        Text(
          'Failed to load',
          style: titleStyle ??
              theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
        ),
      ],
    );
  }
}

/// Compact inline balance display (for use in list items etc.)
class InlineBalanceDisplay extends ConsumerWidget {
  const InlineBalanceDisplay({
    super.key,
    required this.chain,
    this.style,
  });

  final ChainInfo chain;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(chainBalanceProvider(chain));

    return balanceAsync.when(
      data: (balance) {
        if (balance == null) return const SizedBox.shrink();
        final formatted = ref.watch(formattedBalanceProvider(balance));
        return Text(
          formatted,
          style: style ?? theme.textTheme.bodyMedium,
        );
      },
      loading: () => SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            theme.colorScheme.primary,
          ),
        ),
      ),
      error: (_, _) => Text(
        'Error',
        style: style?.copyWith(color: theme.colorScheme.error) ??
            theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
      ),
    );
  }
}
