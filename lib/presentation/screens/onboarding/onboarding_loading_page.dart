import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/chain_provider.dart';
import 'package:wallet_integration_practice/presentation/screens/home/home_screen.dart';
import 'package:wallet_integration_practice/presentation/screens/onboarding/rabby_guide_dialog.dart';

/// Onboarding connection step
enum OnboardingStep {
  openingWallet,
  waitingApproval,
  verifying,
  complete,
  error,
}

/// Onboarding loading page displayed during wallet connection
class OnboardingLoadingPage extends ConsumerStatefulWidget {
  final WalletType walletType;

  /// Whether this page is being restored from a pending connection state.
  /// When true, skips initiating a new connection and just waits for the
  /// existing WalletConnect session to complete.
  final bool isRestoring;

  const OnboardingLoadingPage({
    super.key,
    required this.walletType,
    this.isRestoring = false,
  });

  @override
  ConsumerState<OnboardingLoadingPage> createState() =>
      _OnboardingLoadingPageState();
}

class _OnboardingLoadingPageState extends ConsumerState<OnboardingLoadingPage>
    with SingleTickerProviderStateMixin {
  OnboardingStep _currentStep = OnboardingStep.openingWallet;
  String? _errorMessage;
  StreamSubscription? _connectionSubscription;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Defer provider operations until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToConnectionStatus();

      if (widget.isRestoring) {
        // Restoring from pending state - just wait for session, don't re-initiate
        AppLogger.i('[Onboarding] Restoring from pending state, waiting for session...');
        setState(() => _currentStep = OnboardingStep.waitingApproval);
      } else {
        // Normal flow - add delay to ensure UI is fully rendered before wallet app opens
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _initiateConnection();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _listenToConnectionStatus() {
    final walletService = ref.read(walletServiceProvider);
    _connectionSubscription = walletService.connectionStream.listen(
      (status) {
        AppLogger.d('[Onboarding] Connection status: ${status.state}');

        if (status.isConnected && status.wallet != null) {
          // Connection successful - clear pending state
          ref.read(pendingConnectionServiceProvider).clearPendingConnection();

          setState(() => _currentStep = OnboardingStep.verifying);

          // Brief delay to show verifying step, then complete
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              setState(() => _currentStep = OnboardingStep.complete);
              _navigateToHome();
            }
          });
        } else if (status.hasError) {
          // Connection failed - clear pending state
          ref.read(pendingConnectionServiceProvider).clearPendingConnection();

          setState(() {
            _currentStep = OnboardingStep.error;
            _errorMessage = status.errorMessage ?? 'Connection failed';
          });
        }
      },
      onError: (error) {
        AppLogger.e('[Onboarding] Stream error', error);
        setState(() {
          _currentStep = OnboardingStep.error;
          _errorMessage = error.toString();
        });
      },
    );
  }

  Future<void> _initiateConnection() async {
    // Rabby는 WalletConnect Deep Link를 지원하지 않으므로 안내 다이얼로그 표시
    if (widget.walletType == WalletType.rabby) {
      _showRabbyGuideDialog();
      return;
    }

    setState(() => _currentStep = OnboardingStep.openingWallet);

    // Save pending connection state for app restoration after cold start
    final pendingService = ref.read(pendingConnectionServiceProvider);
    await pendingService.savePendingConnection(widget.walletType);

    try {
      // Get default chain from wallet type
      final defaultChainId = widget.walletType.defaultChainId;
      final defaultCluster = widget.walletType.defaultCluster;

      // Update chain selection for balance display
      final chain = SupportedChains.getByChainId(defaultChainId);
      if (chain != null) {
        ref.read(chainSelectionProvider.notifier).selectChain(chain);
      }

      // Start connection
      await ref.read(multiWalletNotifierProvider.notifier).connectWallet(
            walletType: widget.walletType,
            chainId: defaultChainId,
            cluster: defaultCluster,
          );

      // Wallet app opened, switch to waiting approval
      if (mounted && _currentStep == OnboardingStep.openingWallet) {
        setState(() => _currentStep = OnboardingStep.waitingApproval);
      }
    } on WalletNotInstalledException catch (e) {
      AppLogger.w('Wallet not installed: ${e.walletType}');
      if (mounted) {
        setState(() {
          _currentStep = OnboardingStep.error;
          _errorMessage = '${widget.walletType.displayName}이(가) 설치되어 있지 않습니다.';
        });
      }
    } catch (e) {
      AppLogger.e('Connection error', e);
      if (mounted) {
        setState(() {
          _currentStep = OnboardingStep.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _navigateToHome() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  void _goBack() {
    // Clear pending connection state when user cancels
    ref.read(pendingConnectionServiceProvider).clearPendingConnection();
    Navigator.of(context).pop();
  }

  void _showRabbyGuideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RabbyGuideDialog(
        onCancel: _goBack,
      ),
    );
  }

  Future<void> _openAppStore() async {
    final storeIds = {
      WalletType.metamask: (
        WalletConstants.metamaskAppStoreId,
        WalletConstants.metamaskPackageAndroid
      ),
      WalletType.trustWallet: (
        WalletConstants.trustWalletAppStoreId,
        WalletConstants.trustWalletPackageAndroid
      ),
      WalletType.phantom: (
        WalletConstants.phantomAppStoreId,
        WalletConstants.phantomPackageAndroid
      ),
      WalletType.rabby: (
        WalletConstants.rabbyAppStoreId,
        WalletConstants.rabbyPackageAndroid
      ),
    };

    final ids = storeIds[widget.walletType];
    if (ids == null) return;

    final (appStoreId, packageName) = ids;

    try {
      if (Platform.isIOS) {
        final storeUrl = 'https://apps.apple.com/app/id$appStoreId';
        await launchUrl(
          Uri.parse(storeUrl),
          mode: LaunchMode.externalApplication,
        );
      } else if (Platform.isAndroid) {
        // Try market:// scheme first for direct Play Store opening
        final marketUri = Uri.parse('market://details?id=$packageName');
        final canLaunchMarket = await canLaunchUrl(marketUri);

        if (canLaunchMarket) {
          await launchUrl(marketUri);
        } else {
          // Fallback to web URL
          final webUrl = Uri.parse(
            'https://play.google.com/store/apps/details?id=$packageName',
          );
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      AppLogger.e('Error opening app store', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = _currentStep == OnboardingStep.error;
    final isComplete = _currentStep == OnboardingStep.complete;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),

                      // Wallet icon
                      _buildWalletIcon(theme),

                      const SizedBox(height: 32),

                      // Title
                      Text(
                        isError
                            ? '연결 실패'
                            : isComplete
                                ? '연결 완료!'
                                : '${widget.walletType.displayName}에 연결 중',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isError
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 48),

                      // Progress stepper
                      _buildProgressStepper(theme),

                      const SizedBox(height: 48),

                      // Status message
                      _buildStatusMessage(theme),

                      const Spacer(),

                      // Action buttons (for error state)
                      if (isError) ...[
                        _buildErrorActions(theme),
                        const SizedBox(height: 24),
                      ],

                      // Loading indicator (for non-error, non-complete states)
                      if (!isError && !isComplete) ...[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWalletIcon(ThemeData theme) {
    final isError = _currentStep == OnboardingStep.error;
    final isComplete = _currentStep == OnboardingStep.complete;

    Color iconColor;
    IconData iconData;

    if (isError) {
      iconColor = theme.colorScheme.error;
      iconData = Icons.error_outline;
    } else if (isComplete) {
      iconColor = Colors.green;
      iconData = Icons.check_circle;
    } else {
      iconColor = _getWalletColor(widget.walletType);
      iconData = _getWalletIcon(widget.walletType);
    }

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale =
            isError || isComplete ? 1.0 : 1.0 + (_pulseController.value * 0.05);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: iconColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Icon(
              iconData,
              size: 48,
              color: iconColor,
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressStepper(ThemeData theme) {
    final steps = [
      ('지갑 앱 열기', OnboardingStep.openingWallet),
      ('승인 대기', OnboardingStep.waitingApproval),
      ('서명 검증', OnboardingStep.verifying),
      ('연결 완료', OnboardingStep.complete),
    ];

    return Column(
      children: List.generate(steps.length, (index) {
        final (title, step) = steps[index];
        final isCompleted = _currentStep.index > step.index;
        final isCurrent = _currentStep == step;
        final isError =
            _currentStep == OnboardingStep.error && step.index <= 1;

        return _StepItem(
          title: title,
          isCompleted: isCompleted,
          isCurrent: isCurrent,
          isError: isError && isCurrent == false && isCompleted == false,
          isLast: index == steps.length - 1,
        );
      }),
    );
  }

  Widget _buildStatusMessage(ThemeData theme) {
    String message;
    Color color = theme.colorScheme.onSurfaceVariant;

    switch (_currentStep) {
      case OnboardingStep.openingWallet:
        message = '${widget.walletType.displayName} 앱을 여는 중...';
        break;
      case OnboardingStep.waitingApproval:
        message = '${widget.walletType.displayName}에서 연결을 승인해 주세요.';
        break;
      case OnboardingStep.verifying:
        message = '지갑 정보를 확인하는 중...';
        break;
      case OnboardingStep.complete:
        message = '지갑이 성공적으로 연결되었습니다!';
        color = Colors.green;
        break;
      case OnboardingStep.error:
        message = _errorMessage ?? '연결에 실패했습니다.';
        color = theme.colorScheme.error;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: color,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildErrorActions(ThemeData theme) {
    final isNotInstalled =
        _errorMessage?.contains('설치되어 있지 않습니다') == true;

    return Column(
      children: [
        if (isNotInstalled)
          FilledButton.icon(
            onPressed: _openAppStore,
            icon: const Icon(Icons.download),
            label: Text('${widget.walletType.displayName} 설치'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _goBack,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('돌아가기'),
        ),
      ],
    );
  }

  IconData _getWalletIcon(WalletType type) {
    switch (type) {
      case WalletType.metamask:
        return Icons.account_balance_wallet;
      case WalletType.phantom:
        return Icons.auto_awesome;
      case WalletType.trustWallet:
        return Icons.shield;
      case WalletType.rabby:
        return Icons.pets;
      case WalletType.coinbase:
        return Icons.currency_bitcoin;
      case WalletType.rainbow:
        return Icons.color_lens;
      case WalletType.walletConnect:
        return Icons.link;
      case WalletType.okxWallet:
        return Icons.grid_view; // OKX logo is a grid pattern
    }
  }

  Color _getWalletColor(WalletType type) {
    switch (type) {
      case WalletType.metamask:
        return const Color(0xFFF6851B); // MetaMask orange
      case WalletType.phantom:
        return const Color(0xFFAB9FF2); // Phantom purple
      case WalletType.trustWallet:
        return const Color(0xFF3375BB); // Trust blue
      case WalletType.rabby:
        return const Color(0xFF8697FF); // Rabby purple
      case WalletType.coinbase:
        return const Color(0xFF0052FF); // Coinbase blue
      case WalletType.rainbow:
        return const Color(0xFF001F4D); // Rainbow dark blue
      case WalletType.walletConnect:
        return const Color(0xFF3B99FC); // WalletConnect blue
      case WalletType.okxWallet:
        return const Color(0xFF000000); // OKX black
    }
  }
}

/// Individual step item in the progress stepper
class _StepItem extends StatelessWidget {
  final String title;
  final bool isCompleted;
  final bool isCurrent;
  final bool isError;
  final bool isLast;

  const _StepItem({
    required this.title,
    required this.isCompleted,
    required this.isCurrent,
    required this.isError,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color indicatorColor;
    Widget indicatorChild;

    if (isCompleted) {
      indicatorColor = Colors.green;
      indicatorChild = const Icon(Icons.check, size: 14, color: Colors.white);
    } else if (isCurrent) {
      indicatorColor = theme.colorScheme.primary;
      indicatorChild = Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      );
    } else if (isError) {
      indicatorColor = theme.colorScheme.error;
      indicatorChild =
          const Icon(Icons.close, size: 14, color: Colors.white);
    } else {
      indicatorColor = theme.colorScheme.outlineVariant;
      indicatorChild = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Indicator
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: indicatorColor,
              shape: BoxShape.circle,
            ),
            child: Center(child: indicatorChild),
          ),

          const SizedBox(width: 16),

          // Title
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isCompleted || isCurrent
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),

          // Status icon
          if (isCompleted)
            Icon(
              Icons.check_circle,
              size: 20,
              color: Colors.green,
            )
          else if (isCurrent)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );
  }
}
