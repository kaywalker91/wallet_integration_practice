import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/presentation/providers/session_restoration_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';

/// Full-screen splash widget displayed during session restoration.
///
/// Shows a pulsing logo with progress indicator and status text.
/// Automatically fades out when restoration is complete.
class SessionRestorationSplash extends ConsumerStatefulWidget {
  const SessionRestorationSplash({
    super.key,
    this.onComplete,
    this.minDisplayDuration = const Duration(milliseconds: 800),
  });

  /// Callback when restoration completes and splash fades out.
  final VoidCallback? onComplete;

  /// Minimum duration to display splash (prevents flash for quick restorations).
  final Duration minDisplayDuration;

  @override
  ConsumerState<SessionRestorationSplash> createState() =>
      _SessionRestorationSplashState();
}

class _SessionRestorationSplashState
    extends ConsumerState<SessionRestorationSplash>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  DateTime? _showStartTime;
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();

    _showStartTime = DateTime.now();

    // Pulse animation for logo
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Fade-out animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _handleCompletion() {
    if (_isExiting) return;
    _isExiting = true;

    // Calculate remaining minimum display time
    final elapsed = DateTime.now().difference(_showStartTime!);
    final remaining = widget.minDisplayDuration - elapsed;

    if (remaining > Duration.zero) {
      // Wait for minimum display time, then fade out
      Timer(remaining, _startFadeOut);
    } else {
      // Already past minimum time, fade out immediately
      _startFadeOut();
    }
  }

  void _startFadeOut() {
    _fadeController.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final restorationState = ref.watch(sessionRestorationProvider);

    // Check if restoration is complete
    if (restorationState.isComplete && !_isExiting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleCompletion();
      });
    }

    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: 1.0 - _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0, -20 * _fadeAnimation.value),
            child: child,
          ),
        );
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Animated logo
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: child,
                    );
                  },
                  child: _buildLogo(context, theme),
                ),

                const SizedBox(height: 32),

                // Offline indicator with auto-retry message
                if (restorationState.isOffline)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 18,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '오프라인 상태',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '인터넷 연결 시 자동으로 복원됩니다',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Status text with animated switching
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: _buildStatusText(context, theme, restorationState),
                ),

                const SizedBox(height: 16),

                // Progress indicator
                SizedBox(
                  width: 200,
                  child: _buildProgressIndicator(context, theme, restorationState),
                ),

                const SizedBox(height: 24),

                // Per-wallet status list (shown when there are wallets to restore)
                if (restorationState.wallets.isNotEmpty)
                  _buildWalletStatusList(context, theme, restorationState),

                const Spacer(flex: 3),

                // Timeout skip button (shown after 10 seconds)
                _buildSkipButton(context, theme, restorationState),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context, ThemeData theme) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(
        Icons.account_balance_wallet_rounded,
        size: 40,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildStatusText(
    BuildContext context,
    ThemeData theme,
    SessionRestorationState state,
  ) {
    String text;
    Color textColor = theme.colorScheme.onSurfaceVariant;

    // Show offline-specific message
    if (state.isOffline) {
      final hasWallets = state.wallets.isNotEmpty;
      return Text(
        hasWallets
            ? '저장된 지갑 ${state.wallets.length}개 발견'
            : '네트워크 연결을 기다리는 중...',
        key: ValueKey('offline-${hasWallets ? 'wallets' : 'waiting'}'),
        style: theme.textTheme.bodyLarge?.copyWith(
          color: hasWallets
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      );
    }

    switch (state.phase) {
      case SessionRestorationPhase.initial:
      case SessionRestorationPhase.checking:
        text = '세션을 확인하는 중...';
        break;
      case SessionRestorationPhase.restoring:
        if (state.currentWalletName != null) {
          text = '${state.currentWalletName} 복원 중...';
        } else {
          text = '지갑을 복원하는 중...';
        }
        break;
      case SessionRestorationPhase.completed:
        text = '완료';
        textColor = theme.colorScheme.primary;
        break;
      case SessionRestorationPhase.failed:
        text = state.errorMessage ?? '복원 실패';
        textColor = theme.colorScheme.error;
        break;
      case SessionRestorationPhase.timedOut:
        if (state.hasPartialSuccess) {
          text = '일부 지갑 복원 완료 (${state.restoredSessions}/${state.totalSessions})';
          textColor = theme.colorScheme.tertiary;
        } else {
          text = '연결 시간 초과';
          textColor = theme.colorScheme.error;
        }
        break;
    }

    return Text(
      text,
      key: ValueKey(text),
      style: theme.textTheme.bodyLarge?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w500,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildProgressIndicator(
    BuildContext context,
    ThemeData theme,
    SessionRestorationState state,
  ) {
    if (state.phase == SessionRestorationPhase.restoring &&
        state.totalSessions > 0) {
      // Show determinate progress for multi-wallet restoration
      return Column(
        children: [
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.restoredSessions}/${state.totalSessions}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    // Show indeterminate progress for checking phase
    if (state.isRestoring) {
      return LinearProgressIndicator(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(
          theme.colorScheme.primary,
        ),
        borderRadius: BorderRadius.circular(4),
      );
    }

    // Show nothing when complete
    return const SizedBox.shrink();
  }

  Widget _buildSkipButton(
    BuildContext context,
    ThemeData theme,
    SessionRestorationState state,
  ) {
    // Show continue button for offline mode (background restoration will continue)
    if (state.isOffline && state.wallets.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.tonal(
            onPressed: () {
              // Skip splash and continue to main app
              // Background connectivity listener will restore when online
              ref.read(sessionRestorationProvider.notifier).skip();
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '오프라인으로 계속하기',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '연결되면 자동으로 복원됩니다',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      );
    }

    // Show retry button for timeout/failed states
    if (state.phase == SessionRestorationPhase.timedOut ||
        state.phase == SessionRestorationPhase.failed) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () {
              // Skip and continue to main app
              ref.read(sessionRestorationProvider.notifier).skip();
            },
            child: Text(
              '건너뛰기',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.tonal(
            onPressed: () {
              // Reset state and retry restoration
              ref.read(sessionRestorationProvider.notifier).reset();
              // The wallet notifier will need to be invalidated to retry
              ref.invalidate(walletNotifierProvider);
            },
            child: Text(
              '다시 시도',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      );
    }

    // Only show skip button during restoration and after timeout
    if (!state.isRestoring) {
      return const SizedBox(height: 48);
    }

    final elapsed = state.elapsed;
    final showSkip = elapsed != null && elapsed.inSeconds > 10;

    if (!showSkip) {
      return const SizedBox(height: 48);
    }

    return TextButton(
      onPressed: () {
        ref.read(sessionRestorationProvider.notifier).skip();
      },
      child: Text(
        '건너뛰고 계속하기',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildWalletStatusList(
    BuildContext context,
    ThemeData theme,
    SessionRestorationState state,
  ) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200, maxWidth: 280),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: state.wallets.length,
        itemBuilder: (context, index) {
          final wallet = state.wallets[index];
          return _WalletStatusTile(
            wallet: wallet,
            onRetry: wallet.status == WalletRestorationStatus.failed
                ? () => _retryWallet(wallet.walletId)
                : null,
          );
        },
      ),
    );
  }

  void _retryWallet(String walletId) {
    ref.read(sessionRestorationProvider.notifier).retryWallet(walletId);
    // TODO: Trigger actual wallet restoration retry via wallet provider
    AppLogger.wallet('Retry requested for wallet', data: {'walletId': walletId});
  }
}

/// Individual wallet status tile widget
class _WalletStatusTile extends StatelessWidget {
  const _WalletStatusTile({
    required this.wallet,
    this.onRetry,
  });

  final WalletRestorationInfo wallet;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Wallet icon
          _buildWalletIcon(theme),
          const SizedBox(width: 12),

          // Wallet name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  wallet.walletName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (wallet.errorMessage != null &&
                    wallet.status == WalletRestorationStatus.failed)
                  Text(
                    wallet.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Status indicator
          _buildStatusIndicator(theme),

          // Retry button for failed wallets
          if (wallet.status == WalletRestorationStatus.failed && onRetry != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                onPressed: onRetry,
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                tooltip: '다시 시도',
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWalletIcon(ThemeData theme) {
    IconData iconData;
    Color iconColor;

    // Choose icon based on wallet type
    switch (wallet.walletType.toLowerCase()) {
      case 'phantom':
        iconData = Icons.account_balance_wallet_outlined;
        iconColor = const Color(0xFFAB9FF2); // Phantom purple
        break;
      case 'metamask':
        iconData = Icons.account_balance_wallet;
        iconColor = const Color(0xFFF6851B); // MetaMask orange
        break;
      case 'walletconnect':
        iconData = Icons.link_rounded;
        iconColor = const Color(0xFF3B99FC); // WalletConnect blue
        break;
      default:
        iconData = Icons.wallet_rounded;
        iconColor = theme.colorScheme.primary;
    }

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        iconData,
        size: 18,
        color: iconColor,
      ),
    );
  }

  Widget _buildStatusIndicator(ThemeData theme) {
    switch (wallet.status) {
      case WalletRestorationStatus.pending:
        return Icon(
          Icons.schedule_rounded,
          size: 18,
          color: theme.colorScheme.outline,
        );
      case WalletRestorationStatus.restoring:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.primary,
            ),
          ),
        );
      case WalletRestorationStatus.success:
        return Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: theme.colorScheme.primary,
        );
      case WalletRestorationStatus.failed:
        return Icon(
          Icons.error_rounded,
          size: 18,
          color: theme.colorScheme.error,
        );
      case WalletRestorationStatus.skipped:
        return Icon(
          Icons.skip_next_rounded,
          size: 18,
          color: theme.colorScheme.outline,
        );
    }
  }
}
