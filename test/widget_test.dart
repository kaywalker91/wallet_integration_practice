// Basic Flutter widget tests for SessionRestorationState and related providers.
// Note: Full app widget tests are complex due to async timers in WalletNotifier
// and SessionRestorationSplash. See unit tests for comprehensive coverage.

import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_integration_practice/presentation/providers/session_restoration_provider.dart';

void main() {
  group('SessionRestorationState', () {
    test('initial state has correct default values', () {
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

    test('isRestoring is true during checking and restoring phases', () {
      const checking = SessionRestorationState(
        phase: SessionRestorationPhase.checking,
      );
      const restoring = SessionRestorationState(
        phase: SessionRestorationPhase.restoring,
      );
      const completed = SessionRestorationState(
        phase: SessionRestorationPhase.completed,
      );

      expect(checking.isRestoring, true);
      expect(restoring.isRestoring, true);
      expect(completed.isRestoring, false);
    });

    test('isComplete is true for completed, failed, and timedOut phases', () {
      const completed = SessionRestorationState(
        phase: SessionRestorationPhase.completed,
      );
      const failed = SessionRestorationState(
        phase: SessionRestorationPhase.failed,
      );
      const timedOut = SessionRestorationState(
        phase: SessionRestorationPhase.timedOut,
      );
      const restoring = SessionRestorationState(
        phase: SessionRestorationPhase.restoring,
      );

      expect(completed.isComplete, true);
      expect(failed.isComplete, true);
      expect(timedOut.isComplete, true);
      expect(restoring.isComplete, false);
    });

    test('progress is calculated correctly', () {
      const noSessions = SessionRestorationState(
        totalSessions: 0,
        restoredSessions: 0,
      );
      const halfDone = SessionRestorationState(
        totalSessions: 4,
        restoredSessions: 2,
      );
      const allDone = SessionRestorationState(
        totalSessions: 3,
        restoredSessions: 3,
      );

      expect(noSessions.progress, 0.0);
      expect(halfDone.progress, 0.5);
      expect(allDone.progress, 1.0);
    });

    test('hasPartialSuccess identifies timeout with restored sessions', () {
      const timedOutNoSessions = SessionRestorationState(
        phase: SessionRestorationPhase.timedOut,
        restoredSessions: 0,
      );
      const timedOutWithSessions = SessionRestorationState(
        phase: SessionRestorationPhase.timedOut,
        restoredSessions: 2,
      );
      const completedWithSessions = SessionRestorationState(
        phase: SessionRestorationPhase.completed,
        restoredSessions: 2,
      );

      expect(timedOutNoSessions.hasPartialSuccess, false);
      expect(timedOutWithSessions.hasPartialSuccess, true);
      expect(completedWithSessions.hasPartialSuccess, false);
    });

    test('copyWith creates new instance with updated fields', () {
      const original = SessionRestorationState(
        phase: SessionRestorationPhase.checking,
        totalSessions: 3,
      );

      final updated = original.copyWith(
        phase: SessionRestorationPhase.restoring,
        restoredSessions: 1,
      );

      expect(updated.phase, SessionRestorationPhase.restoring);
      expect(updated.totalSessions, 3); // Unchanged
      expect(updated.restoredSessions, 1); // Updated
    });

    test('copyWith clears optional fields when requested', () {
      const original = SessionRestorationState(
        currentWalletName: 'MetaMask',
        errorMessage: 'Some error',
      );

      final cleared = original.copyWith(
        clearCurrentWallet: true,
        clearError: true,
      );

      expect(cleared.currentWalletName, isNull);
      expect(cleared.errorMessage, isNull);
    });
  });

  group('WalletRestorationInfo', () {
    test('has correct default status', () {
      const info = WalletRestorationInfo(
        walletId: 'test_1',
        walletName: 'Test Wallet',
        walletType: 'metamask',
      );

      expect(info.status, WalletRestorationStatus.pending);
      expect(info.isProcessing, false);
      expect(info.isComplete, false);
    });

    test('isProcessing is true only during restoring', () {
      const restoring = WalletRestorationInfo(
        walletId: 'test_1',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.restoring,
      );
      const success = WalletRestorationInfo(
        walletId: 'test_2',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.success,
      );

      expect(restoring.isProcessing, true);
      expect(success.isProcessing, false);
    });

    test('isComplete is true for success, failed, and skipped', () {
      const success = WalletRestorationInfo(
        walletId: 'test_1',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.success,
      );
      const failed = WalletRestorationInfo(
        walletId: 'test_2',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.failed,
      );
      const skipped = WalletRestorationInfo(
        walletId: 'test_3',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.skipped,
      );
      const pending = WalletRestorationInfo(
        walletId: 'test_4',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.pending,
      );

      expect(success.isComplete, true);
      expect(failed.isComplete, true);
      expect(skipped.isComplete, true);
      expect(pending.isComplete, false);
    });

    test('copyWith updates status and error', () {
      const original = WalletRestorationInfo(
        walletId: 'test_1',
        walletName: 'Test',
        walletType: 'metamask',
        status: WalletRestorationStatus.restoring,
      );

      final failed = original.copyWith(
        status: WalletRestorationStatus.failed,
        errorMessage: 'Connection lost',
      );

      expect(failed.status, WalletRestorationStatus.failed);
      expect(failed.errorMessage, 'Connection lost');
      expect(failed.walletId, 'test_1'); // Unchanged
    });
  });

  group('SessionRestorationState wallet helpers', () {
    test('failedCount counts failed wallets', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: '1',
            walletName: 'A',
            walletType: 'metamask',
            status: WalletRestorationStatus.success,
          ),
          WalletRestorationInfo(
            walletId: '2',
            walletName: 'B',
            walletType: 'phantom',
            status: WalletRestorationStatus.failed,
          ),
          WalletRestorationInfo(
            walletId: '3',
            walletName: 'C',
            walletType: 'walletconnect',
            status: WalletRestorationStatus.failed,
          ),
        ],
      );

      expect(state.failedCount, 2);
      expect(state.hasFailures, true);
    });

    test('pendingCount counts pending wallets', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: '1',
            walletName: 'A',
            walletType: 'metamask',
            status: WalletRestorationStatus.pending,
          ),
          WalletRestorationInfo(
            walletId: '2',
            walletName: 'B',
            walletType: 'phantom',
            status: WalletRestorationStatus.restoring,
          ),
          WalletRestorationInfo(
            walletId: '3',
            walletName: 'C',
            walletType: 'walletconnect',
            status: WalletRestorationStatus.pending,
          ),
        ],
      );

      expect(state.pendingCount, 2);
    });

    test('getWalletById finds wallet by id', () {
      const state = SessionRestorationState(
        wallets: [
          WalletRestorationInfo(
            walletId: 'mm_1',
            walletName: 'MetaMask',
            walletType: 'metamask',
          ),
          WalletRestorationInfo(
            walletId: 'ph_1',
            walletName: 'Phantom',
            walletType: 'phantom',
          ),
        ],
      );

      final found = state.getWalletById('ph_1');
      final notFound = state.getWalletById('unknown');

      expect(found?.walletName, 'Phantom');
      expect(notFound, isNull);
    });
  });
}