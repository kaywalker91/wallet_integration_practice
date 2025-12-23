import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wallet_integration_practice/core/constants/app_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/data/models/wallet_model.dart';
import 'package:wallet_integration_practice/data/models/persisted_session_model.dart';
import 'package:wallet_integration_practice/data/models/phantom_session_model.dart';

/// Local data source for wallet persistence
abstract class WalletLocalDataSource {
  /// Save connected wallet session
  Future<void> saveWalletSession(WalletModel wallet);

  /// Get saved wallet session
  Future<WalletModel?> getWalletSession();

  /// Clear wallet session
  Future<void> clearWalletSession();

  /// Save session topic
  Future<void> saveSessionTopic(String topic);

  /// Get session topic
  Future<String?> getSessionTopic();

  /// Clear session topic
  Future<void> clearSessionTopic();

  // Session Persistence for App Restart Recovery

  /// Save persisted session for app restart recovery
  Future<void> savePersistedSession(PersistedSessionModel session);

  /// Get persisted session
  Future<PersistedSessionModel?> getPersistedSession();

  /// Clear persisted session
  Future<void> clearPersistedSession();

  /// Update persisted session's last used timestamp
  Future<void> updatePersistedSessionLastUsed();

  // Phantom Session Persistence (X25519 key-based)

  /// Save Phantom session for app restart recovery
  Future<void> savePhantomSession(PhantomSessionModel session);

  /// Get persisted Phantom session
  Future<PhantomSessionModel?> getPhantomSession();

  /// Clear Phantom session
  Future<void> clearPhantomSession();

  /// Update Phantom session's last used timestamp
  Future<void> updatePhantomSessionLastUsed();
}

/// Implementation of WalletLocalDataSource using FlutterSecureStorage
class WalletLocalDataSourceImpl implements WalletLocalDataSource {
  WalletLocalDataSourceImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _secureStorage;

  @override
  Future<void> saveWalletSession(WalletModel wallet) async {
    try {
      final json = jsonEncode(wallet.toJson());
      await _secureStorage.write(
        key: AppConstants.walletSessionKey,
        value: json,
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to save wallet session',
        originalException: e,
      );
    }
  }

  @override
  Future<WalletModel?> getWalletSession() async {
    try {
      final json = await _secureStorage.read(key: AppConstants.walletSessionKey);
      if (json == null) return null;
      return WalletModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      throw StorageException(
        message: 'Failed to get wallet session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> clearWalletSession() async {
    try {
      await _secureStorage.delete(key: AppConstants.walletSessionKey);
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear wallet session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> saveSessionTopic(String topic) async {
    try {
      await _secureStorage.write(
        key: '${AppConstants.walletSessionKey}_topic',
        value: topic,
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to save session topic',
        originalException: e,
      );
    }
  }

  @override
  Future<String?> getSessionTopic() async {
    try {
      return await _secureStorage.read(
        key: '${AppConstants.walletSessionKey}_topic',
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to get session topic',
        originalException: e,
      );
    }
  }

  @override
  Future<void> clearSessionTopic() async {
    try {
      await _secureStorage.delete(
        key: '${AppConstants.walletSessionKey}_topic',
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear session topic',
        originalException: e,
      );
    }
  }

  // Session Persistence Implementation

  @override
  Future<void> savePersistedSession(PersistedSessionModel session) async {
    try {
      final json = jsonEncode(session.toJson());
      await _secureStorage.write(
        key: AppConstants.persistedSessionKey,
        value: json,
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to save persisted session',
        originalException: e,
      );
    }
  }

  @override
  Future<PersistedSessionModel?> getPersistedSession() async {
    try {
      final json = await _secureStorage.read(
        key: AppConstants.persistedSessionKey,
      );
      if (json == null) return null;
      return PersistedSessionModel.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (e) {
      // If there's a parsing error, clear the corrupted data
      await _secureStorage.delete(key: AppConstants.persistedSessionKey);
      throw StorageException(
        message: 'Failed to get persisted session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> clearPersistedSession() async {
    try {
      await _secureStorage.delete(key: AppConstants.persistedSessionKey);
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear persisted session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> updatePersistedSessionLastUsed() async {
    try {
      final session = await getPersistedSession();
      if (session == null) return;

      final updated = PersistedSessionModel(
        walletType: session.walletType,
        sessionTopic: session.sessionTopic,
        address: session.address,
        chainId: session.chainId,
        cluster: session.cluster,
        createdAt: session.createdAt,
        lastUsedAt: DateTime.now(),
        expiresAt: session.expiresAt,
      );

      await savePersistedSession(updated);
    } catch (e) {
      // Non-critical operation, don't throw
    }
  }

  // Phantom Session Persistence Implementation

  @override
  Future<void> savePhantomSession(PhantomSessionModel session) async {
    try {
      final json = jsonEncode(session.toJson());
      await _secureStorage.write(
        key: AppConstants.phantomSessionKey,
        value: json,
      );
    } catch (e) {
      throw StorageException(
        message: 'Failed to save Phantom session',
        originalException: e,
      );
    }
  }

  @override
  Future<PhantomSessionModel?> getPhantomSession() async {
    try {
      final json = await _secureStorage.read(
        key: AppConstants.phantomSessionKey,
      );
      if (json == null) return null;
      return PhantomSessionModel.fromJson(
        jsonDecode(json) as Map<String, dynamic>,
      );
    } catch (e) {
      // If there's a parsing error, clear the corrupted data
      await _secureStorage.delete(key: AppConstants.phantomSessionKey);
      throw StorageException(
        message: 'Failed to get Phantom session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> clearPhantomSession() async {
    try {
      await _secureStorage.delete(key: AppConstants.phantomSessionKey);
    } catch (e) {
      throw StorageException(
        message: 'Failed to clear Phantom session',
        originalException: e,
      );
    }
  }

  @override
  Future<void> updatePhantomSessionLastUsed() async {
    try {
      final session = await getPhantomSession();
      if (session == null) return;

      final updated = session.copyWithLastUsed(DateTime.now());
      await savePhantomSession(updated);
    } catch (e) {
      // Non-critical operation, don't throw
    }
  }
}
