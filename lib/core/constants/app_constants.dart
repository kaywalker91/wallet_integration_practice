import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Wallet Integration Practice';
  static const String appVersion = '1.0.0';

  /// SIWS (Sign In With Solana) 메시지에 사용할 앱 도메인
  static const String appDomain = 'ilityhub.com';

  // WalletConnect
  static String get walletConnectProjectId => dotenv.env['WALLETCONNECT_PROJECT_ID'] ?? '';
  static const String walletConnectRelayUrl = 'wss://relay.walletconnect.com';

  // App Metadata for WalletConnect
  static const String appUrl = 'https://ility.io';
  static const String appDescription = 'iLity Hub Wallet Integration Practice';
  static const String appIcon = 'https://ility.io/icon.png';

  // Deep Link Schemes
  static const String deepLinkScheme = 'wip';
  static const String universalLinkHost = 'ility.io';

  // dApp URL for in-app browser connections (e.g., Rabby)
  // NOTE: Currently pointing to development server
  static const String dappUrl = 'https://ility-hub.dev.forlong.io/leaderboard/top-asset';

  // Storage Keys
  static const String walletSessionKey = 'wallet_session';
  static const String connectedWalletKey = 'connected_wallet';
  static const String preferredChainKey = 'preferred_chain';

  // Timeouts
  // Extended from 60s to 120s to accommodate:
  // - User review time in wallet app
  // - Android background network restrictions (Doze mode)
  // - OKX Wallet's slower session propagation
  static const Duration connectionTimeout = Duration(seconds: 120);
  static const Duration connectionRetryDelay = Duration(seconds: 2);
  static const int maxConnectionRetries = 3;
  static const Duration signatureTimeout = Duration(minutes: 2);

  /// Grace period after timeout before showing error
  /// Allows deep link callback to arrive and process
  static const Duration deepLinkGracePeriod = Duration(milliseconds: 500);

  // OKX Wallet 전용 재연결 설정
  // - Android 백그라운드 네트워크 제한으로 인한 Relay 끊김 대응
  // - 포그라운드 복귀 시 공격적 재연결 수행
  static const List<int> okxReconnectTimeouts = [3, 4, 5]; // 초 단위, 점진적 증가
  static const Duration okxReconnectDelay = Duration(milliseconds: 300);
  static const Duration okxPrePollDelay = Duration(milliseconds: 1000);
  static const Duration okxSessionPollInterval = Duration(seconds: 1);
  static const int okxMaxSessionPolls = 5;
}
