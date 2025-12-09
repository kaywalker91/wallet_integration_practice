import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_integration_practice/core/core.dart';

/// 대기 중인 지갑 연결 상태를 관리하는 서비스
///
/// 앱이 백그라운드에서 종료된 후 Cold Start될 때,
/// 대기 중인 연결이 있으면 OnboardingLoadingPage로 복원할 수 있도록 합니다.
class PendingConnectionService {
  PendingConnectionService(this._prefs);

  static const String _keyPendingWalletType = 'pending_wallet_type';
  static const String _keyPendingTimestamp = 'pending_timestamp';

  /// 연결 대기 만료 시간 (5분)
  static const Duration _expirationDuration = Duration(minutes: 5);

  final SharedPreferences _prefs;

  /// 대기 중인 연결 저장
  Future<void> savePendingConnection(WalletType walletType) async {
    await _prefs.setString(_keyPendingWalletType, walletType.name);
    await _prefs.setInt(
        _keyPendingTimestamp, DateTime.now().millisecondsSinceEpoch);
    AppLogger.i('Saved pending connection for: ${walletType.name}');
  }

  /// 대기 중인 연결 삭제
  Future<void> clearPendingConnection() async {
    await _prefs.remove(_keyPendingWalletType);
    await _prefs.remove(_keyPendingTimestamp);
    AppLogger.i('Cleared pending connection');
  }

  /// 유효한 대기 중 연결이 있는지 확인
  ///
  /// 5분 이내의 대기 중 연결이 있으면 해당 WalletType을 반환,
  /// 없거나 만료되었으면 null 반환
  WalletType? getPendingConnection() {
    final walletTypeName = _prefs.getString(_keyPendingWalletType);
    final timestamp = _prefs.getInt(_keyPendingTimestamp);

    if (walletTypeName == null || timestamp == null) return null;

    // 만료 여부 확인
    final savedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(savedTime) > _expirationDuration) {
      AppLogger.i('Pending connection expired, clearing...');
      clearPendingConnection();
      return null;
    }

    // WalletType으로 변환
    try {
      final walletType =
          WalletType.values.firstWhere((t) => t.name == walletTypeName);
      AppLogger.i('Found valid pending connection: ${walletType.name}');
      return walletType;
    } catch (_) {
      AppLogger.w('Invalid wallet type in pending connection: $walletTypeName');
      clearPendingConnection();
      return null;
    }
  }

  /// 대기 중인 연결이 있는지 확인 (만료 여부 무관)
  bool hasPendingConnection() {
    return _prefs.getString(_keyPendingWalletType) != null;
  }
}
