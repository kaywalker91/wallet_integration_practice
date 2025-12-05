import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:wallet_integration_practice/core/constants/app_constants.dart';
import 'package:wallet_integration_practice/core/errors/exceptions.dart';
import 'package:wallet_integration_practice/data/models/wallet_model.dart';

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
}

/// Implementation of WalletLocalDataSource using FlutterSecureStorage
class WalletLocalDataSourceImpl implements WalletLocalDataSource {
  final FlutterSecureStorage _secureStorage;

  WalletLocalDataSourceImpl({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

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
}
