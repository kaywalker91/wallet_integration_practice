import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Application-wide constants
class AppConstants {
  AppConstants._();

  // App Info
  static const String appName = 'Wallet Integration Practice';
  static const String appVersion = '1.0.0';

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
  static const String dappUrl = 'https://app.ility.io';

  // Storage Keys
  static const String walletSessionKey = 'wallet_session';
  static const String connectedWalletKey = 'connected_wallet';
  static const String preferredChainKey = 'preferred_chain';

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 60);
  static const Duration connectionRetryDelay = Duration(seconds: 2);
  static const int maxConnectionRetries = 3;
  static const Duration signatureTimeout = Duration(minutes: 2);
}
