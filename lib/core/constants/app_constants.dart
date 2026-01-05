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
  static const String persistedSessionKey = 'persisted_session_v1';
  static const String phantomSessionKey = 'phantom_session_v1';

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

  /// OKX Wallet용 relay 전파 마진 딜레이
  /// prepareConnection() 반환 후에도 네트워크 지연을 고려한 버퍼
  /// 지갑 앱이 relay에서 session proposal을 조회하기 전 충분한 전파 시간 확보
  /// 600ms → 1500ms로 증가하여 첫 연결 시 race condition 방지
  static const Duration okxRelayPropagationDelay = Duration(milliseconds: 1500);

  // Soft Timeout 설정
  // - 백그라운드에서 발생한 타임아웃은 "soft timeout"으로 처리
  // - 사용자가 앱으로 돌아오면 세션 복구 시도

  /// Soft timeout 판정 기준 (백그라운드 시간이 이 이상이면 soft timeout)
  static const Duration softTimeoutThreshold = Duration(seconds: 3);

  /// 백그라운드로 인한 타임아웃 연장 최대값
  static const Duration maxBackgroundTimeoutExtension = Duration(seconds: 60);

  /// Soft timeout 후 복구 대기 시간
  static const Duration postSoftTimeoutRecoveryWindow = Duration(seconds: 30);

  // ============================================================
  // Session Persistence Feature Flags
  // ============================================================

  /// Enable WalletConnect session topic format validation.
  /// When enabled, validates that session topics are 64-char hex strings.
  static const bool enableTopicFormatValidation = true;

  /// Enable fallback session search by address when topic lookup fails.
  /// When enabled, if a session topic is not found, searches by wallet address.
  static const bool enableSessionAddressFallback = true;

  /// Enable persistence retry queue for failed session save operations.
  /// When enabled, failed persistence operations are retried with exponential backoff.
  static const bool enablePersistenceRetryQueue = true;

  /// Enable strict session validation (requires relay connection).
  /// When false, uses lenient mode that allows offline validation.
  /// Recommended: Start with false, enable after monitoring.
  static const bool enableStrictSessionValidation = false;

  /// Enable Phantom encryption key validation during session restore.
  /// When enabled, validates dApp and Phantom keys before accepting restored session.
  static const bool enablePhantomKeyValidation = true;

  /// Session validation timeout for relay connectivity check.
  static const Duration sessionValidationTimeout = Duration(seconds: 5);

  /// Maximum retries for persistence operations.
  static const int maxPersistenceRetries = 3;

  /// Retry interval for persistence operations.
  static const Duration persistenceRetryInterval = Duration(seconds: 5);

  /// Enable generalized reconnection configuration.
  /// When true, uses WalletReconnectionConfig for all wallets.
  /// When false, uses legacy OKX-specific constants.
  static const bool enableGeneralizedReconnectionConfig = true;

  // ======== Session Persistence Feature Flags ========

  /// Enable offline-first session validation.
  /// When enabled, validates sessions locally before attempting relay connection.
  /// Reduces perceived latency and handles offline scenarios gracefully.
  static const bool enableOfflineFirstValidation = true;

  /// Enable persistent recovery state for MetaMask.
  /// When enabled, recovery state survives process death using SharedPreferences.
  static const bool enableMetaMaskPersistentRecovery = true;

  /// Enable persistent recovery state for OKX Wallet.
  /// When enabled, recovery state survives process death using SharedPreferences.
  static const bool enableOkxPersistentRecovery = true;

  /// Maximum time to wait for relay propagation after session is established.
  /// Used for both initial connection and restoration.
  static const Duration maxRelayPropagationWait = Duration(milliseconds: 2000);

  /// Recovery state validity duration.
  /// Recovery states older than this will be automatically cleaned up.
  static const Duration recoveryStateValidity = Duration(minutes: 5);

  // ============================================================
  // Address Validation Feature Flags
  // ============================================================

  /// Enable address format validation before RPC calls.
  /// When enabled, validates that address format matches the target chain type
  /// (e.g., EVM addresses start with 0x, Solana addresses are Base58).
  /// Set to false to rollback if validation causes issues.
  static const bool enableAddressValidation = true;

  // ============================================================
  // Relay Connection Feature Flags
  // ============================================================

  /// Enable relay connection state machine for WebSocket stability.
  /// When enabled, uses RelayConnectionStateMachine to prevent race conditions.
  static const bool useRelayStateMachine = true;

  /// Delay in milliseconds between relay disconnect and reconnect.
  /// Increased from 300ms to allow complete WebSocket stream cleanup.
  static const int relayCleanupDelayMs = 500;

  // ============================================================
  // Phantom Performance Feature Flags
  // ============================================================

  /// Enable isolate-based crypto operations for Phantom wallet.
  /// When enabled, decryption runs in background isolate to prevent UI jank.
  static const bool useIsolateCrypto = true;

  /// Enable async (fire-and-forget) session persistence.
  /// When enabled, session saving doesn't block the connection flow.
  static const bool useAsyncSessionPersistence = true;
}
