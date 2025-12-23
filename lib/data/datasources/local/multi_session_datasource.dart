import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wallet_integration_practice/core/constants/app_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/data/models/multi_session_model.dart';
import 'package:wallet_integration_practice/data/models/persisted_session_model.dart';
import 'package:wallet_integration_practice/data/models/phantom_session_model.dart';
import 'package:wallet_integration_practice/domain/entities/multi_session_state.dart';

/// Storage key for multi-session state
const String _multiSessionStorageKey = 'multi_wallet_sessions_v1';

/// Abstract interface for multi-session storage operations
abstract class MultiSessionDataSource {
  /// Get all stored sessions
  Future<MultiSessionStateModel> getAllSessions();

  /// Save a WalletConnect-based session
  Future<void> saveWalletConnectSession({
    required String walletId,
    required PersistedSessionModel session,
  });

  /// Save a Phantom session
  Future<void> savePhantomSession({
    required String walletId,
    required PhantomSessionModel session,
  });

  /// Get a specific session by walletId
  Future<MultiSessionEntryModel?> getSession(String walletId);

  /// Remove a session by walletId
  Future<void> removeSession(String walletId);

  /// Clear all sessions
  Future<void> clearAllSessions();

  /// Set active wallet ID
  Future<void> setActiveWalletId(String? walletId);

  /// Get active wallet ID
  Future<String?> getActiveWalletId();

  /// Update session's last used timestamp
  Future<void> updateSessionLastUsed(String walletId);

  /// Remove all expired sessions
  Future<int> removeExpiredSessions();

  /// Migrate legacy single-session data to multi-session format
  Future<bool> migrateLegacySessions();
}

/// Implementation of MultiSessionDataSource using FlutterSecureStorage
class MultiSessionDataSourceImpl implements MultiSessionDataSource {
  MultiSessionDataSourceImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  @override
  Future<MultiSessionStateModel> getAllSessions() async {
    try {
      final json = await _secureStorage.read(key: _multiSessionStorageKey);
      if (json == null) {
        return MultiSessionStateModel.empty();
      }
      return MultiSessionStateModel.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (e) {
      // Log error but return empty state instead of throwing
      // ignore: avoid_print
      print('Failed to get multi-session state: $e');
      return MultiSessionStateModel.empty();
    }
  }

  Future<void> _saveState(MultiSessionStateModel state) async {
    try {
      final json = jsonEncode(state.toJson());
      await _secureStorage.write(
        key: _multiSessionStorageKey,
        value: json,
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to save multi-session state',
        originalException: e,
      );
    }
  }

  @override
  Future<void> saveWalletConnectSession({
    required String walletId,
    required PersistedSessionModel session,
  }) async {
    try {
      final currentState = await getAllSessions();
      final entry = MultiSessionEntryModel.fromWalletConnect(
        walletId: walletId,
        session: session,
      );
      final updatedState = currentState.addSession(entry);
      await _saveState(updatedState);
    } catch (e) {
      throw StorageException(
        message: 'Failed to save WalletConnect session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> savePhantomSession({
    required String walletId,
    required PhantomSessionModel session,
  }) async {
    try {
      final currentState = await getAllSessions();
      final entry = MultiSessionEntryModel.fromPhantom(
        walletId: walletId,
        session: session,
      );
      final updatedState = currentState.addSession(entry);
      await _saveState(updatedState);
    } catch (e) {
      throw StorageException(
        message: 'Failed to save Phantom session',
        originalException: e,
      );
    }
  }

  @override
  Future<MultiSessionEntryModel?> getSession(String walletId) async {
    try {
      final state = await getAllSessions();
      return state.getSession(walletId);
    } catch (e) {
      throw StorageException(
        message: 'Failed to get session: $walletId',
        originalException: e,
      );
    }
  }

  @override
  Future<void> removeSession(String walletId) async {
    try {
      final currentState = await getAllSessions();
      final updatedState = currentState.removeSession(walletId);
      await _saveState(updatedState);
    } catch (e) {
      throw StorageException(
        message: 'Failed to remove session: $walletId',
        originalException: e,
      );
    }
  }

  @override
  Future<void> clearAllSessions() async {
    try {
      await _secureStorage.delete(key: _multiSessionStorageKey);
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear all sessions',
        originalException: e,
      );
    }
  }

  @override
  Future<void> setActiveWalletId(String? walletId) async {
    try {
      final currentState = await getAllSessions();
      final updatedState = currentState.setActiveWallet(walletId);
      await _saveState(updatedState);
    } catch (e) {
      throw StorageException(
        message: 'Failed to set active wallet',
        originalException: e,
      );
    }
  }

  @override
  Future<String?> getActiveWalletId() async {
    try {
      final state = await getAllSessions();
      return state.activeWalletId;
    } catch (e) {
      // Non-critical, return null
      return null;
    }
  }

  @override
  Future<void> updateSessionLastUsed(String walletId) async {
    try {
      final currentState = await getAllSessions();
      final session = currentState.getSession(walletId);
      if (session == null) return;

      final updatedSession = session.copyWithLastUsed(DateTime.now());
      final updatedState = currentState.addSession(updatedSession);
      await _saveState(updatedState);
    } catch (e) {
      // Non-critical operation, don't throw
      // ignore: avoid_print
      print('Failed to update session last used: $e');
    }
  }

  @override
  Future<int> removeExpiredSessions() async {
    try {
      final currentState = await getAllSessions();
      final expiredCount = currentState.sessionList
          .where((s) => s.toEntity().isExpired)
          .length;

      if (expiredCount == 0) return 0;

      final validSessions = <String, MultiSessionEntryModel>{};
      for (final entry in currentState.sessions.entries) {
        if (!entry.value.toEntity().isExpired) {
          validSessions[entry.key] = entry.value;
        }
      }

      final updatedState = MultiSessionStateModel(
        sessions: validSessions,
        activeWalletId: validSessions.containsKey(currentState.activeWalletId)
            ? currentState.activeWalletId
            : null,
      );

      await _saveState(updatedState);
      return expiredCount;
    } catch (e) {
      // Non-critical operation, don't throw
      // ignore: avoid_print
      print('Failed to remove expired sessions: $e');
      return 0;
    }
  }

  @override
  Future<bool> migrateLegacySessions() async {
    try {
      // Check if migration is already done
      final existingState = await getAllSessions();
      if (existingState.isNotEmpty) {
        // Already have multi-session data, skip migration
        return false;
      }

      var migrated = false;

      // Try to migrate legacy WalletConnect session
      final legacyWcJson = await _secureStorage.read(
        key: AppConstants.persistedSessionKey,
      );
      if (legacyWcJson != null) {
        try {
          final legacySession = PersistedSessionModel.fromJson(
            jsonDecode(legacyWcJson) as Map<String, dynamic>,
          );

          // Check if session is not expired
          if (!legacySession.toEntity().isExpired) {
            final walletId = WalletIdGenerator.generate(
              legacySession.walletType,
              legacySession.address,
            );
            await saveWalletConnectSession(
              walletId: walletId,
              session: legacySession,
            );
            await setActiveWalletId(walletId);
            migrated = true;
          }

          // Clear legacy data after migration
          await _secureStorage.delete(key: AppConstants.persistedSessionKey);
        } catch (e) {
          // Failed to parse legacy session, clear it
          await _secureStorage.delete(key: AppConstants.persistedSessionKey);
        }
      }

      // Try to migrate legacy Phantom session
      final legacyPhantomJson = await _secureStorage.read(
        key: AppConstants.phantomSessionKey,
      );
      if (legacyPhantomJson != null) {
        try {
          final legacySession = PhantomSessionModel.fromJson(
            jsonDecode(legacyPhantomJson) as Map<String, dynamic>,
          );

          // Check if session is not expired
          if (!legacySession.toEntity().isExpired) {
            final walletId = WalletIdGenerator.generate(
              'phantom',
              legacySession.connectedAddress,
            );
            await savePhantomSession(
              walletId: walletId,
              session: legacySession,
            );

            // Only set as active if no WalletConnect session was migrated
            final state = await getAllSessions();
            if (state.activeWalletId == null) {
              await setActiveWalletId(walletId);
            }
            migrated = true;
          }

          // Clear legacy data after migration
          await _secureStorage.delete(key: AppConstants.phantomSessionKey);
        } catch (e) {
          // Failed to parse legacy session, clear it
          await _secureStorage.delete(key: AppConstants.phantomSessionKey);
        }
      }

      return migrated;
    } catch (e) {
      // Migration failed, but don't throw - app can continue without legacy data
      // ignore: avoid_print
      print('Session migration failed: $e');
      return false;
    }
  }
}
