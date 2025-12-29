import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_integration_practice/presentation/providers/session_restoration_provider.dart';

void main() {
  group('SessionRestorationState', () {
    test('initial state has correct defaults', () {
      const state = SessionRestorationState();

      expect(state.phase, SessionRestorationPhase.initial);
      expect(state.totalSessions, 0);
      expect(state.restoredSessions, 0);
      expect(state.currentWalletName, isNull);
      expect(state.errorMessage, isNull);
      expect(state.startedAt, isNull);
      expect(state.isOffline, false);
      expect(state.wallets, isEmpty);
    });

    test('isRestoring returns true during checking phase', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.checking,
      );

      expect(state.isRestoring, true);
    });

    test('isRestoring returns true during restoring phase', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.restoring,
      );

      expect(state.isRestoring, true);
    });

    test('isRestoring returns false when completed', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.completed,
      );

      expect(state.isRestoring, false);
    });

    test('isComplete returns true for completed phase', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.completed,
      );

      expect(state.isComplete, true);
    });

    test('isComplete returns true for failed phase', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.failed,
      );

      expect(state.isComplete, true);
    });

    test('isComplete returns true for timedOut phase', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.timedOut,
      );

      expect(state.isComplete, true);
    });

    test('progress calculation is correct', () {
      const state = SessionRestorationState(
        totalSessions: 4,
        restoredSessions: 2,
      );

      expect(state.progress, 0.5);
    });

    test('progress returns 0 when totalSessions is 0', () {
      const state = SessionRestorationState(
        totalSessions: 0,
        restoredSessions: 0,
      );

      expect(state.progress, 0.0);
    });

    test('hasPartialSuccess returns true when timeout with restored sessions', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.timedOut,
        totalSessions: 3,
        restoredSessions: 1,
      );

      expect(state.hasPartialSuccess, true);
    });

    test('hasPartialSuccess returns false when timeout with no restored sessions', () {
      const state = SessionRestorationState(
        phase: SessionRestorationPhase.timedOut,
        totalSessions: 3,
        restoredSessions: 0,
      );

      expect(state.hasPartialSuccess, false);
    });

    test('elapsed returns duration since startedAt', () {
      final startTime = DateTime.now().subtract(const Duration(seconds: 5));
      final state = SessionRestorationState(
        startedAt: startTime,
      );

      final elapsed = state.elapsed;
      expect(elapsed, isNotNull);
      expect(elapsed!.inSeconds, greaterThanOrEqualTo(5));
    });

    test('elapsed returns null when startedAt is null', () {
      const state = SessionRestorationState();

      expect(state.elapsed, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const original = SessionRestorationState(
        phase: SessionRestorationPhase.restoring,
        totalSessions: 5,
        restoredSessions: 2,
        currentWalletName: 'MetaMask',
      );

      final copied = original.copyWith(restoredSessions: 3);

      expect(copied.phase, SessionRestorationPhase.restoring);
      expect(copied.totalSessions, 5);
      expect(copied.restoredSessions, 3);
      expect(copied.currentWalletName, 'MetaMask');
    });

    test('copyWith with clearCurrentWallet sets currentWalletName to null', () {
      const original = SessionRestorationState(
        currentWalletName: 'MetaMask',
      );

      final copied = original.copyWith(clearCurrentWallet: true);

      expect(copied.currentWalletName, isNull);
    });

    test('copyWith with clearError sets errorMessage to null', () {
      const original = SessionRestorationState(
        errorMessage: 'Some error',
      );

      final copied = original.copyWith(clearError: true);

      expect(copied.errorMessage, isNull);
    });
  });

  group('WalletRestorationInfo', () {
    test('initial state has correct defaults', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
      );

      expect(info.walletId, 'wallet-1');
      expect(info.walletName, 'MetaMask');
      expect(info.walletType, 'metaMask');
      expect(info.status, WalletRestorationStatus.pending);
      expect(info.errorMessage, isNull);
      expect(info.iconPath, isNull);
    });

    test('isProcessing returns true when restoring', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.restoring,
      );

      expect(info.isProcessing, true);
    });

    test('isProcessing returns false when not restoring', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.pending,
      );

      expect(info.isProcessing, false);
    });

    test('isComplete returns true for success status', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.success,
      );

      expect(info.isComplete, true);
    });

    test('isComplete returns true for failed status', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.failed,
      );

      expect(info.isComplete, true);
    });

    test('isComplete returns true for skipped status', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.skipped,
      );

      expect(info.isComplete, true);
    });

    test('isComplete returns false for pending status', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.pending,
      );

      expect(info.isComplete, false);
    });

    test('copyWith updates status correctly', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        status: WalletRestorationStatus.pending,
      );

      final updated = info.copyWith(status: WalletRestorationStatus.success);

      expect(updated.status, WalletRestorationStatus.success);
      expect(updated.walletId, 'wallet-1');
      expect(updated.walletName, 'MetaMask');
    });

    test('copyWith with clearError sets errorMessage to null', () {
      const info = WalletRestorationInfo(
        walletId: 'wallet-1',
        walletName: 'MetaMask',
        walletType: 'metaMask',
        errorMessage: 'Some error',
      );

      final updated = info.copyWith(clearError: true);

      expect(updated.errorMessage, isNull);
    });
  });

  group('SessionRestorationState wallet helpers', () {
    test('failedCount returns correct count', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'w1',
            walletName: 'MetaMask',
            walletType: 'metaMask',
            status: WalletRestorationStatus.failed,
          ),
          WalletRestorationInfo(
            walletId: 'w2',
            walletName: 'Phantom',
            walletType: 'phantom',
            status: WalletRestorationStatus.success,
          ),
          WalletRestorationInfo(
            walletId: 'w3',
            walletName: 'Rainbow',
            walletType: 'rainbow',
            status: WalletRestorationStatus.failed,
          ),
        ],
      );

      expect(state.failedCount, 2);
    });

    test('pendingCount returns correct count', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'w1',
            walletName: 'MetaMask',
            walletType: 'metaMask',
            status: WalletRestorationStatus.pending,
          ),
          WalletRestorationInfo(
            walletId: 'w2',
            walletName: 'Phantom',
            walletType: 'phantom',
            status: WalletRestorationStatus.success,
          ),
        ],
      );

      expect(state.pendingCount, 1);
    });

    test('hasFailures returns true when failures exist', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'w1',
            walletName: 'MetaMask',
            walletType: 'metaMask',
            status: WalletRestorationStatus.failed,
          ),
        ],
      );

      expect(state.hasFailures, true);
    });

    test('hasFailures returns false when no failures', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'w1',
            walletName: 'MetaMask',
            walletType: 'metaMask',
            status: WalletRestorationStatus.success,
          ),
        ],
      );

      expect(state.hasFailures, false);
    });

    test('getWalletById returns wallet when found', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'w1',
            walletName: 'MetaMask',
            walletType: 'metaMask',
          ),
          WalletRestorationInfo(
            walletId: 'w2',
            walletName: 'Phantom',
            walletType: 'phantom',
          ),
        ],
      );

      final wallet = state.getWalletById('w2');

      expect(wallet, isNotNull);
      expect(wallet!.walletName, 'Phantom');
    });

    test('getWalletById returns null when not found', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'w1',
            walletName: 'MetaMask',
            walletType: 'metaMask',
          ),
        ],
      );

      final wallet = state.getWalletById('non-existent');

      expect(wallet, isNull);
    });
  });

  group('SessionRestorationNotifier', () {
    late ProviderContainer container;
    late SessionRestorationNotifier notifier;

    setUp(() {
      container = ProviderContainer();
      notifier = container.read(sessionRestorationProvider.notifier);
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is correct', () {
      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.initial);
      expect(state.totalSessions, 0);
    });

    test('startChecking sets phase to checking', () {
      notifier.startChecking();

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.checking);
      expect(state.startedAt, isNotNull);
    });

    test('beginRestoration sets phase to restoring with wallet list', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
        const WalletRestorationInfo(
          walletId: 'w2',
          walletName: 'Phantom',
          walletType: 'phantom',
        ),
      ];

      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 2, wallets: wallets);

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.restoring);
      expect(state.totalSessions, 2);
      expect(state.wallets.length, 2);
      expect(state.restoredSessions, 0);
    });

    test('initWallets initializes wallet list', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
      ];

      notifier.initWallets(wallets);

      final state = container.read(sessionRestorationProvider);

      expect(state.wallets.length, 1);
      expect(state.totalSessions, 1);
    });

    test('updateWalletStatus updates wallet status correctly', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
      ];

      notifier.initWallets(wallets);
      notifier.updateWalletStatus(
        walletId: 'w1',
        status: WalletRestorationStatus.success,
      );

      final state = container.read(sessionRestorationProvider);
      final wallet = state.getWalletById('w1');

      expect(wallet!.status, WalletRestorationStatus.success);
    });

    test('updateWalletStatus updates restoredSessions count', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
        const WalletRestorationInfo(
          walletId: 'w2',
          walletName: 'Phantom',
          walletType: 'phantom',
        ),
      ];

      notifier.initWallets(wallets);
      notifier.updateWalletStatus(
        walletId: 'w1',
        status: WalletRestorationStatus.success,
      );

      final state = container.read(sessionRestorationProvider);

      expect(state.restoredSessions, 1);
    });

    test('startWalletRestoration sets wallet to restoring', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
      ];

      notifier.initWallets(wallets);
      notifier.startWalletRestoration('w1');

      final state = container.read(sessionRestorationProvider);
      final wallet = state.getWalletById('w1');

      expect(wallet!.status, WalletRestorationStatus.restoring);
      expect(state.currentWalletName, 'MetaMask');
    });

    test('walletRestorationSuccess sets wallet to success', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
      ];

      notifier.initWallets(wallets);
      notifier.walletRestorationSuccess('w1');

      final state = container.read(sessionRestorationProvider);
      final wallet = state.getWalletById('w1');

      expect(wallet!.status, WalletRestorationStatus.success);
    });

    test('walletRestorationFailed sets wallet to failed with error', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
      ];

      notifier.initWallets(wallets);
      notifier.walletRestorationFailed('w1', 'Connection timeout');

      final state = container.read(sessionRestorationProvider);
      final wallet = state.getWalletById('w1');

      expect(wallet!.status, WalletRestorationStatus.failed);
      expect(wallet.errorMessage, 'Connection timeout');
    });

    test('retryWallet sets wallet back to pending', () {
      final wallets = [
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
          status: WalletRestorationStatus.failed,
        ),
      ];

      notifier.initWallets(wallets);
      notifier.retryWallet('w1');

      final state = container.read(sessionRestorationProvider);
      final wallet = state.getWalletById('w1');

      expect(wallet!.status, WalletRestorationStatus.pending);
    });

    test('updateProgress updates progress correctly', () {
      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 3);
      notifier.updateProgress(restoredCount: 2, currentWalletName: 'Phantom');

      final state = container.read(sessionRestorationProvider);

      expect(state.restoredSessions, 2);
      expect(state.currentWalletName, 'Phantom');
    });

    test('complete sets phase to completed', () {
      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 2);
      notifier.complete();

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.completed);
      expect(state.currentWalletName, isNull);
    });

    test('completeNoSessions sets phase to completed with zero sessions', () {
      notifier.startChecking();
      notifier.completeNoSessions();

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.completed);
      expect(state.totalSessions, 0);
      expect(state.restoredSessions, 0);
    });

    test('fail sets phase to failed with error message', () {
      notifier.startChecking();
      notifier.fail('Network error');

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.failed);
      expect(state.errorMessage, 'Network error');
      expect(state.currentWalletName, isNull);
    });

    test('skip sets phase to completed', () {
      notifier.startChecking();
      notifier.skip();

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.completed);
    });

    test('timeout sets phase to timedOut with message', () {
      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 3);
      notifier.updateProgress(restoredCount: 1);
      notifier.timeout(restoredCount: 1);

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.timedOut);
      expect(state.restoredSessions, 1);
      expect(state.errorMessage, contains('timed out'));
    });

    test('reset returns to initial state', () {
      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 3);
      notifier.reset();

      final state = container.read(sessionRestorationProvider);

      expect(state.phase, SessionRestorationPhase.initial);
      expect(state.totalSessions, 0);
      expect(state.wallets, isEmpty);
    });

    test('setOffline updates offline status', () {
      notifier.setOffline(true);

      final state = container.read(sessionRestorationProvider);

      expect(state.isOffline, true);
    });

    test('setOffline does not update if same value', () {
      notifier.setOffline(false);

      // Should not trigger unnecessary state changes
      final state1 = container.read(sessionRestorationProvider);
      notifier.setOffline(false);
      final state2 = container.read(sessionRestorationProvider);

      // States should be identical (same instance)
      expect(identical(state1, state2), true);
    });
  });

  group('Derived Providers', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('isRestoringSessionsProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(isRestoringSessionsProvider), false);

      notifier.startChecking();
      expect(container.read(isRestoringSessionsProvider), true);

      notifier.complete();
      expect(container.read(isRestoringSessionsProvider), false);
    });

    test('appInitializedProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(appInitializedProvider), false);

      notifier.startChecking();
      expect(container.read(appInitializedProvider), false);

      notifier.complete();
      expect(container.read(appInitializedProvider), true);
    });

    test('restorationProgressProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 4);
      notifier.updateProgress(restoredCount: 2);

      expect(container.read(restorationProgressProvider), 0.5);
    });

    test('restorationPhaseProvider returns current phase', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(
        container.read(restorationPhaseProvider),
        SessionRestorationPhase.initial,
      );

      notifier.startChecking();
      expect(
        container.read(restorationPhaseProvider),
        SessionRestorationPhase.checking,
      );
    });

    test('restorationErrorProvider returns error message', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(restorationErrorProvider), isNull);

      notifier.fail('Test error');
      expect(container.read(restorationErrorProvider), 'Test error');
    });

    test('currentRestoringWalletProvider returns wallet name', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(currentRestoringWalletProvider), isNull);

      notifier.updateProgress(restoredCount: 0, currentWalletName: 'MetaMask');
      expect(container.read(currentRestoringWalletProvider), 'MetaMask');
    });

    test('restorationTimedOutProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(restorationTimedOutProvider), false);

      notifier.startChecking();
      notifier.timeout();
      expect(container.read(restorationTimedOutProvider), true);
    });

    test('restorationPartialSuccessProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      notifier.startChecking();
      notifier.beginRestoration(totalSessions: 3);
      notifier.updateProgress(restoredCount: 1);
      notifier.timeout(restoredCount: 1);

      expect(container.read(restorationPartialSuccessProvider), true);
    });

    test('restorationOfflineProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(restorationOfflineProvider), false);

      notifier.setOffline(true);
      expect(container.read(restorationOfflineProvider), true);
    });

    test('walletRestorationListProvider returns wallet list', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(walletRestorationListProvider), isEmpty);

      notifier.initWallets([
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
        ),
      ]);

      expect(container.read(walletRestorationListProvider).length, 1);
    });

    test('failedWalletsProvider returns only failed wallets', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      notifier.initWallets([
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
          status: WalletRestorationStatus.failed,
        ),
        const WalletRestorationInfo(
          walletId: 'w2',
          walletName: 'Phantom',
          walletType: 'phantom',
          status: WalletRestorationStatus.success,
        ),
      ]);

      final failedWallets = container.read(failedWalletsProvider);

      expect(failedWallets.length, 1);
      expect(failedWallets.first.walletId, 'w1');
    });

    test('hasWalletFailuresProvider returns correct value', () {
      final notifier = container.read(sessionRestorationProvider.notifier);

      expect(container.read(hasWalletFailuresProvider), false);

      notifier.initWallets([
        const WalletRestorationInfo(
          walletId: 'w1',
          walletName: 'MetaMask',
          walletType: 'metaMask',
          status: WalletRestorationStatus.failed,
        ),
      ]);

      expect(container.read(hasWalletFailuresProvider), true);
    });
  });
}
