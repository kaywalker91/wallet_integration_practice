import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/presentation/providers/session_restoration_provider.dart';

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
}
