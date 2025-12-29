import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';
import 'package:wallet_integration_practice/domain/entities/multi_wallet_state.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/providers/chain_provider.dart';
import 'package:wallet_integration_practice/presentation/screens/home/home_screen.dart';
import 'package:wallet_integration_practice/presentation/screens/onboarding/rabby_guide_dialog.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';

/// Onboarding connection step
enum OnboardingStep {
  openingWallet,
  waitingApproval,
  signingIn, // SIWS: Sign In With Solana (Phantom only)
  verifying,
  complete,
  error,
}

/// Onboarding loading page displayed during wallet connection
class OnboardingLoadingPage extends ConsumerStatefulWidget {
  const OnboardingLoadingPage({
    super.key,
    required this.walletType,
    this.isRestoring = false,
  });

  final WalletType walletType;

  /// Whether this page is being restored from a pending connection state.
  /// When true, skips initiating a new connection and just waits for the
  /// existing WalletConnect session to complete.
  final bool isRestoring;

  @override
  ConsumerState<OnboardingLoadingPage> createState() =>
      _OnboardingLoadingPageState();
}

class _OnboardingLoadingPageState extends ConsumerState<OnboardingLoadingPage>
    with SingleTickerProviderStateMixin {
  OnboardingStep _currentStep = OnboardingStep.openingWallet;
  String? _errorMessage;
  late AnimationController _pulseController;
  ProviderSubscription<MultiWalletState>? _walletStateSubscription;
  DateTime? _connectionStartedAt;
  bool _hasHandledSuccess = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Defer provider operations until after the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startWalletStateListener();

      if (widget.isRestoring) {
        // Restoring from pending state - initialize adapter and check for existing session
        AppLogger.i('[Onboarding] Restoring from pending state...');
        setState(() => _currentStep = OnboardingStep.waitingApproval);
        _restoreAndCheckSession();
      } else {
        // Add delay to ensure UI is fully rendered before wallet app opens
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_isWalletTypeConnected()) {
            _initiateConnection();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _walletStateSubscription?.close();
    _pulseController.dispose();
    super.dispose();
  }

  void _startWalletStateListener() {
    if (_walletStateSubscription != null) return;

    _walletStateSubscription = ref.listenManual<MultiWalletState>(
      multiWalletNotifierProvider,
      (_, next) => _syncFromWalletState(next),
      fireImmediately: true,
    );
  }

  void _syncFromWalletState(MultiWalletState state) {
    if (!mounted || _hasHandledSuccess) return;

    final entry = _selectRelevantEntry(state);
    if (entry == null) return;

    switch (entry.status) {
      case WalletEntryStatus.connected:
        if (widget.isRestoring) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted && !_hasHandledSuccess) {
              _handleConnectionSuccess(entry.wallet);
            }
          });
        } else {
          _handleConnectionSuccess(entry.wallet);
        }
        break;
      case WalletEntryStatus.connecting:
        if (_currentStep == OnboardingStep.openingWallet) {
          setState(() => _currentStep = OnboardingStep.waitingApproval);
        }
        break;
      case WalletEntryStatus.error:
        ref.read(pendingConnectionServiceProvider).clearPendingConnection();
        setState(() {
          _currentStep = OnboardingStep.error;
          _errorMessage = entry.errorMessage ?? '연결에 실패했습니다.';
        });
        break;
      case WalletEntryStatus.disconnected:
        break;
    }
  }

  ConnectedWalletEntry? _selectRelevantEntry(MultiWalletState state) {
    final entries = state.wallets
        .where((entry) => entry.wallet.type == widget.walletType)
        .toList();

    if (entries.isEmpty) return null;

    final connectedEntries = entries
        .where((entry) => entry.status == WalletEntryStatus.connected)
        .toList();
    if (connectedEntries.isNotEmpty) {
      connectedEntries
          .sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
      return connectedEntries.first;
    }

    if (_connectionStartedAt == null) return null;

    final recentEntries = entries
        .where((entry) => !entry.lastActivityAt.isBefore(_connectionStartedAt!))
        .toList();
    if (recentEntries.isEmpty) return null;

    recentEntries
        .sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    return recentEntries.first;
  }

  bool _isWalletTypeConnected() {
    final state = ref.read(multiWalletNotifierProvider);
    return state.wallets.any((entry) =>
        entry.wallet.type == widget.walletType &&
        entry.status == WalletEntryStatus.connected);
  }

  /// Handle successful wallet connection
  Future<void> _handleConnectionSuccess(WalletEntity wallet) async {
    if (_hasHandledSuccess) return;
    _hasHandledSuccess = true;

    // Clear pending state
    await ref.read(pendingConnectionServiceProvider).clearPendingConnection();

    AppLogger.wallet('[Onboarding] Connection successful', data: {
      'address': wallet.address,
      'type': wallet.type.name,
    });

    // Ensure state is synced before navigation
    ref.read(multiWalletNotifierProvider.notifier).registerWallet(wallet);

    // SIWS: Phantom 지갑의 경우 서명 인증 수행
    if (wallet.type == WalletType.phantom) {
      setState(() => _currentStep = OnboardingStep.signingIn);

      try {
        final walletService = ref.read(walletServiceProvider);
        final signature = await walletService.signInWithSolana(
          domain: AppConstants.appDomain,
          statement: 'iLity Hub 로그인을 확인해주세요.',
        );
        AppLogger.wallet('[Onboarding] SIWS completed', data: {
          'signaturePreview': signature.length > 20 ? '${signature.substring(0, 20)}...' : signature,
        });
      } catch (e) {
        // SIWS 실패해도 연결은 유지 (선택적 정책)
        AppLogger.w('[Onboarding] SIWS failed (connection retained): $e');
      }
    }

    setState(() => _currentStep = OnboardingStep.verifying);

    // Brief delay to show verifying step, then complete
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _currentStep = OnboardingStep.complete);
        _navigateToHome();
      }
    });
  }

  /// Restore session after cold start.
  ///
  /// This is called when the app was killed while waiting for wallet approval,
  /// and the user returns from the wallet app. We need to:
  /// 1. Re-initialize the wallet adapter (which restores session from storage)
  /// 2. Ensure relay WebSocket is connected (CRITICAL after cold start!)
  /// 3. Check if the stored session is valid and usable
  /// 4. If connected, proceed to home; otherwise, retry up to maxRetries times
  ///
  /// Key improvement: Uses a retry loop with "Bad state" error absorption
  /// to handle socket race conditions during OKX wallet reconnection.
  Future<void> _restoreAndCheckSession() async {
    AppLogger.i('[Onboarding] Restoring session for ${widget.walletType.name}...');
    _connectionStartedAt = DateTime.now();

    // Maximum retry attempts (about 15 seconds total)
    const maxRetries = 15;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        // Check if already connected via MultiWallet state
        final existingEntry =
            _selectRelevantEntry(ref.read(multiWalletNotifierProvider));
        if (existingEntry != null &&
            existingEntry.status == WalletEntryStatus.connected) {
          AppLogger.i('[Onboarding] Wallet already connected via MultiWallet');
          await _handleConnectionSuccess(existingEntry.wallet);
          return;
        }

        // Update UI to show we're restoring (only on first attempt)
        if (mounted && _currentStep != OnboardingStep.verifying) {
          setState(() => _currentStep = OnboardingStep.verifying);
        }

        // Get the wallet service
        final walletService = ref.read(walletServiceProvider);

        // Initialize adapter WITHOUT creating a new connection
        // This restores the session from storage and attempts relay reconnection
        if (attempt == 0) {
          AppLogger.i('[Onboarding] Initializing adapter for restoration...');
        }
        final adapter = await walletService.initializeAdapter(widget.walletType);

        // CRITICAL: For WalletConnect adapters, verify relay is connected
        // After cold start (Android process death), the WebSocket is dead
        // even though session objects are restored from storage
        if (adapter is WalletConnectAdapter) {
          if (attempt == 0) {
            AppLogger.i('[Onboarding] Checking relay connection...');
          } else {
            AppLogger.i('[Onboarding] Attempt ${attempt + 1}/$maxRetries: Checking relay...');
          }

          // ensureRelayConnected now handles "Bad state" errors internally
          await adapter.ensureRelayConnected(
            timeout: const Duration(seconds: 5),
          );

          // Wait for session to propagate after relay reconnection
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // Check if we're now connected after relay reconnection
        final status = walletService.currentConnectionStatus;
        if (status.isConnected &&
            status.wallet != null &&
            status.wallet!.type == widget.walletType) {
          AppLogger.i('[Onboarding] Session restored successfully on attempt ${attempt + 1}!');

          // Clear pending state
          await ref.read(pendingConnectionServiceProvider).clearPendingConnection();

          // Register wallet
          ref.read(multiWalletNotifierProvider.notifier).registerWallet(status.wallet!);

          // Update chain selection for balance display
          final defaultChainId = widget.walletType.defaultChainId;
          final chain = SupportedChains.getByChainId(defaultChainId);
          if (chain != null) {
            ref.read(chainSelectionProvider.notifier).selectChain(chain);
          }

          // Show success briefly then navigate
          if (mounted) {
            setState(() => _currentStep = OnboardingStep.complete);
            await Future.delayed(const Duration(milliseconds: 800));
            _navigateToHome();
          }
          return;
        }

        // Session not found yet - wait before retry
        if (attempt < maxRetries - 1) {
          AppLogger.i('[Onboarding] No session yet, retrying in 1s... (${attempt + 1}/$maxRetries)');
          await Future.delayed(const Duration(seconds: 1));
        }

      } catch (e) {
        // === CRITICAL: Absorb "Bad state" errors and continue retrying ===
        // These errors occur during socket handoff and are transient
        if (e.toString().contains('Bad state') || e.toString().contains('closed')) {
          AppLogger.w('[Onboarding] Socket error ignored, retrying... ($e)');
          if (attempt < maxRetries - 1) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        } else {
          // Other errors - log but continue retrying unless it's the last attempt
          AppLogger.w('[Onboarding] Error on attempt ${attempt + 1}: $e');
          if (attempt < maxRetries - 1) {
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
        }
      }
    }

    // All retries exhausted - show error
    AppLogger.w('[Onboarding] All $maxRetries attempts failed');
    await ref.read(pendingConnectionServiceProvider).clearPendingConnection();

    if (mounted) {
      setState(() {
        _currentStep = OnboardingStep.error;
        _errorMessage = '세션을 복원할 수 없습니다. 다시 연결해 주세요.';
      });
    }
  }

  Future<void> _initiateConnection() async {
    // Rabby는 WalletConnect Deep Link를 지원하지 않으므로 안내 다이얼로그 표시
    if (widget.walletType == WalletType.rabby) {
      _showRabbyGuideDialog();
      return;
    }

    setState(() => _currentStep = OnboardingStep.openingWallet);
    _connectionStartedAt = DateTime.now();

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
      WalletType.okxWallet: (
        WalletConstants.okxWalletAppStoreId,
        WalletConstants.okxWalletPackageAndroid
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

                      const SizedBox(height: 16),

                      // Recovery options (shown after 15s timeout)
                      _buildRecoveryOptions(theme),

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

    Color borderColor;
    Color backgroundColor;
    Widget iconWidget;

    if (isError) {
      borderColor = theme.colorScheme.error;
      backgroundColor = theme.colorScheme.error.withValues(alpha: 0.1);
      iconWidget = Icon(
        Icons.error_outline,
        size: 48,
        color: theme.colorScheme.error,
      );
    } else if (isComplete) {
      borderColor = Colors.green;
      backgroundColor = Colors.green.withValues(alpha: 0.1);
      iconWidget = const Icon(
        Icons.check_circle,
        size: 48,
        color: Colors.green,
      );
    } else {
      borderColor = _getWalletColor(widget.walletType).withValues(alpha: 0.3);
      backgroundColor = _getWalletColor(widget.walletType).withValues(alpha: 0.1);
      iconWidget = Image.asset(
        widget.walletType.iconAsset,
        width: 48,
        height: 48,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.account_balance_wallet,
          size: 48,
          color: _getWalletColor(widget.walletType),
        ),
      );
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
              color: backgroundColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: borderColor,
                width: 2,
              ),
            ),
            padding: const EdgeInsets.all(20), // Add padding for the image
            child: Center(child: iconWidget),
          ),
        );
      },
    );
  }

  Widget _buildProgressStepper(ThemeData theme) {
    // Phantom 지갑인 경우 SIWS 단계 포함
    final isPhantom = widget.walletType == WalletType.phantom;

    final steps = [
      ('지갑 앱 열기', OnboardingStep.openingWallet),
      ('승인 대기', OnboardingStep.waitingApproval),
      if (isPhantom) ('서명 인증', OnboardingStep.signingIn),
      ('연결 확인', OnboardingStep.verifying),
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
      case OnboardingStep.signingIn:
        message = '${widget.walletType.displayName}에서 서명을 승인해 주세요.';
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

  /// Build recovery options UI
  /// Shows when approval timeout is reached (15 seconds)
  Widget _buildRecoveryOptions(ThemeData theme) {
    final showRecovery = ref.watch(showRecoveryOptionsProvider);
    final connectionUri = ref.watch(recoveryConnectionUriProvider);
    final recoveryWalletType = ref.watch(recoveryWalletTypeProvider);

    // Only show during waiting approval step
    if (!showRecovery ||
        _currentStep != OnboardingStep.waitingApproval ||
        recoveryWalletType != widget.walletType) {
      return const SizedBox.shrink();
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '승인 화면이 안 보이시나요?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // QR Code option
            if (connectionUri != null) ...[
              _RecoveryOptionButton(
                icon: Icons.qr_code_2,
                label: 'QR 코드로 연결',
                subtitle: '지갑 앱에서 스캔하세요',
                onTap: () => _showQrCodeDialog(context, connectionUri),
              ),
              const SizedBox(height: 8),

              // Copy URI option
              _RecoveryOptionButton(
                icon: Icons.copy,
                label: '연결 URI 복사',
                subtitle: '지갑 앱에 직접 붙여넣기',
                onTap: () => _copyConnectionUri(connectionUri),
              ),
              const SizedBox(height: 8),
            ],

            // Retry option
            _RecoveryOptionButton(
              icon: Icons.refresh,
              label: '다시 시도',
              subtitle: '연결을 처음부터 다시 시작',
              onTap: _retryConnection,
            ),
          ],
        ),
      ),
    );
  }

  /// Show QR code dialog for connection
  void _showQrCodeDialog(BuildContext context, String uri) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.qr_code_2, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('QR 코드로 연결'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: uri,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${widget.walletType.displayName} 앱에서\nQR 코드를 스캔하세요',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uri));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URI가 클립보드에 복사되었습니다'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('URI 복사'),
          ),
        ],
      ),
    );
  }

  /// Copy connection URI to clipboard
  void _copyConnectionUri(String uri) {
    Clipboard.setData(ClipboardData(text: uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('연결 URI가 클립보드에 복사되었습니다'),
        action: SnackBarAction(
          label: '확인',
          onPressed: () {},
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Retry connection from scratch
  void _retryConnection() {
    // Reset recovery state
    ref.read(connectionRecoveryProvider.notifier).reset();

    // Reset step and restart
    setState(() {
      _currentStep = OnboardingStep.openingWallet;
      _errorMessage = null;
    });
    _connectionStartedAt = DateTime.now();

    // Re-initiate connection
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _initiateConnection();
      }
    });
  }

  Color _getWalletColor(WalletType type) {
    switch (type) {
      case WalletType.metamask:
        return const Color(0xFFF6851B); // MetaMask orange
      case WalletType.phantom:
        return const Color(0xFFAB9FF2); // Phantom purple
      case WalletType.trustWallet:
        return const Color(0xFF3375BB); // Trust blue
      case WalletType.okxWallet:
        return const Color(0xFF1E6FE8); // OKX blue
      case WalletType.rabby:
        return const Color(0xFF8697FF); // Rabby purple
      case WalletType.coinbase:
        return const Color(0xFF0052FF); // Coinbase blue
      case WalletType.rainbow:
        return const Color(0xFF001F4D); // Rainbow dark blue
      case WalletType.walletConnect:
        return const Color(0xFF3B99FC); // WalletConnect blue
    }
  }
}

/// Individual step item in the progress stepper
class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.title,
    required this.isCompleted,
    required this.isCurrent,
    required this.isError,
    required this.isLast,
  });

  final String title;
  final bool isCompleted;
  final bool isCurrent;
  final bool isError;
  final bool isLast;

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
            const Icon(
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

/// Recovery option button for connection troubleshooting
class _RecoveryOptionButton extends StatelessWidget {
  const _RecoveryOptionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
