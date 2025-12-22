import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:wallet_integration_practice/core/services/debug_log_service.dart';
import 'package:wallet_integration_practice/core/utils/logger.dart';

/// Sentry 에러 트래킹 서비스
///
/// 앱 전반의 에러를 실시간으로 포착하고 분석하기 위한 서비스입니다.
/// - 자동 에러 수집 (Uncaught Exceptions)
/// - 수동 에러 캡처 (try-catch)
/// - Breadcrumbs (유저 행동 추적)
/// - Tags (에러 필터링 및 그룹화)
/// - User Context (유저 식별)
class SentryService {
  SentryService._();
  static final SentryService instance = SentryService._();

  bool _isInitialized = false;

  /// Sentry 초기화 여부
  bool get isInitialized => _isInitialized;

  /// Sentry 초기화
  ///
  /// [appRunner]에 runApp을 전달하여 앱 전체를 Sentry로 감싸줍니다.
  static Future<void> initialize({
    required Future<void> Function() appRunner,
  }) async {
    final dsn = dotenv.env['SENTRY_DSN'];

    // DSN이 없거나 디버그 모드면 Sentry 비활성화
    if (dsn == null || dsn.isEmpty) {
      AppLogger.w('Sentry DSN not configured, skipping initialization');
      await appRunner();
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;

        // 환경 설정
        options.environment = kDebugMode ? 'development' : 'production';

        // 트레이스 샘플링 비율 (프로덕션은 0.1~0.2 권장)
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;

        // 디버그 모드 설정
        options.debug = kDebugMode;

        // 앱 릴리즈 버전 (빌드 시 설정)
        options.release = dotenv.env['APP_VERSION'] ?? '1.0.0';

        // 자동 세션 트래킹
        options.autoSessionTrackingInterval = const Duration(seconds: 30);

        // [Debug Mode] beforeSend 콜백으로 로그 인터셉트
        // Sentry로 전송되는 모든 이벤트를 콘솔에 출력하고 메모리에 저장합니다.
        // 프로덕션에서는 비활성화되어 성능에 영향을 주지 않습니다.
        if (kDebugMode) {
          options.beforeSend = (SentryEvent event, Hint hint) {
            // 1. 콘솔에 로그 출력
            _printEventToConsole(event);

            // 2. 메모리에 저장 (Provider로 접근 가능)
            final entry = DebugLogEntry.fromSentryEvent(event);
            DebugLogService.instance.addLog(entry);

            // 3. 이벤트를 그대로 반환 (Sentry로 전송 계속)
            return event;
          };
        }
      },
      appRunner: () async {
        // Set initialized flag before running the app
        instance._isInitialized = true;
        AppLogger.i('Sentry initialized successfully');

        // Now run the actual app
        await appRunner();
      },
    );
  }

  // ============================================================================
  // Error Capture (에러 전송)
  // ============================================================================

  /// 예외를 Sentry로 전송
  ///
  /// [exception]: 발생한 예외
  /// [stackTrace]: 스택 트레이스
  /// [extras]: 추가 컨텍스트 데이터
  /// [tags]: 필터링용 태그
  /// [level]: 에러 레벨
  Future<void> captureException(
    dynamic exception, {
    StackTrace? stackTrace,
    Map<String, dynamic>? extras,
    Map<String, String>? tags,
    SentryLevel? level,
  }) async {
    if (!_isInitialized) {
      AppLogger.w('Sentry not initialized, skipping exception capture');
      return;
    }

    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      withScope: (scope) {
        // 추가 데이터를 Context로 설정 (setExtra deprecated)
        if (extras != null && extras.isNotEmpty) {
          scope.setContexts('extra_data', extras);
        }

        // 태그 설정
        if (tags != null) {
          tags.forEach((key, value) {
            scope.setTag(key, value);
          });
        }

        // 에러 레벨 설정
        if (level != null) {
          scope.level = level;
        }
      },
    );
  }

  /// 메시지를 Sentry로 전송 (경고/정보성 로그)
  Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
    Map<String, dynamic>? extras,
    Map<String, String>? tags,
  }) async {
    if (!_isInitialized) return;

    await Sentry.captureMessage(
      message,
      level: level,
      withScope: (scope) {
        // 추가 데이터를 Context로 설정 (setExtra deprecated)
        if (extras != null && extras.isNotEmpty) {
          scope.setContexts('extra_data', extras);
        }
        if (tags != null) {
          tags.forEach((key, value) {
            scope.setTag(key, value);
          });
        }
      },
    );
  }

  // ============================================================================
  // Breadcrumbs (유저 행동 추적)
  // ============================================================================

  /// Breadcrumb 추가 (유저 행동 타임라인)
  ///
  /// 에러 발생 직전의 유저 행동을 기록합니다.
  void addBreadcrumb({
    required String message,
    String? category,
    Map<String, dynamic>? data,
    SentryLevel level = SentryLevel.info,
  }) {
    if (!_isInitialized) return;

    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        data: data,
        level: level,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// 유저 액션 Breadcrumb (버튼 클릭 등)
  void addUserAction(String action, {Map<String, dynamic>? data}) {
    addBreadcrumb(
      message: action,
      category: 'user.action',
      data: data,
    );
  }

  /// 네비게이션 Breadcrumb (화면 이동)
  void addNavigation({
    required String from,
    required String to,
  }) {
    addBreadcrumb(
      message: 'Navigation: $from -> $to',
      category: 'navigation',
      data: {'from': from, 'to': to},
    );
  }

  /// 네트워크 요청 Breadcrumb
  void addNetworkRequest({
    required String url,
    required String method,
    int? statusCode,
    String? error,
  }) {
    addBreadcrumb(
      message: '$method $url',
      category: 'http',
      data: {
        'url': url,
        'method': method,
        if (statusCode != null) 'status_code': statusCode,
        if (error != null) 'error': error,
      },
      level: error != null ? SentryLevel.error : SentryLevel.info,
    );
  }

  // ============================================================================
  // Tags & Context (검색/필터용 메타데이터)
  // ============================================================================

  /// 전역 태그 설정 (검색 필터용)
  void setTag(String key, String value) {
    if (!_isInitialized) return;

    Sentry.configureScope((scope) {
      scope.setTag(key, value);
    });
  }

  /// 여러 태그 한번에 설정
  void setTags(Map<String, String> tags) {
    if (!_isInitialized) return;

    Sentry.configureScope((scope) {
      tags.forEach((key, value) {
        scope.setTag(key, value);
      });
    });
  }

  /// 전역 Extra 데이터 설정 (Context 사용 권장)
  ///
  /// NOTE: setExtra는 deprecated되었으므로 [setContext]를 사용하는 것이 좋습니다.
  void setExtra(String key, dynamic value) {
    if (!_isInitialized) return;

    // setExtra deprecated, use setContexts instead
    Sentry.configureScope((scope) {
      scope.setContexts('extras', {key: value});
    });
  }

  /// Context 설정 (그룹화된 추가 정보)
  void setContext(String key, Map<String, dynamic> value) {
    if (!_isInitialized) return;

    Sentry.configureScope((scope) {
      scope.setContexts(key, value);
    });
  }

  // ============================================================================
  // User Context (유저 식별)
  // ============================================================================

  /// 유저 정보 설정
  ///
  /// CS 대응 시 어떤 유저가 문제를 겪었는지 식별 가능
  void setUser({
    String? id,
    String? email,
    String? username,
    Map<String, String>? data,
  }) {
    if (!_isInitialized) return;

    Sentry.configureScope((scope) {
      scope.setUser(SentryUser(
        id: id,
        email: email,
        username: username,
        data: data,
      ));
    });
  }

  /// 유저 정보 제거 (로그아웃 시)
  void clearUser() {
    if (!_isInitialized) return;

    Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  }

  // ============================================================================
  // Wallet-Specific Methods (지갑 앱 전용)
  // ============================================================================

  /// 지갑 연결 시작 추적
  void trackWalletConnectionStart({
    required String walletType,
    int? chainId,
    String? cluster,
  }) {
    addBreadcrumb(
      message: 'Wallet connection started',
      category: 'wallet.connection',
      data: {
        'wallet_type': walletType,
        if (chainId != null) 'chain_id': chainId,
        if (cluster != null) 'cluster': cluster,
      },
    );

    setTags({
      'wallet_type': walletType,
      if (chainId != null) 'chain_id': chainId.toString(),
    });
  }

  /// 지갑 연결 성공 추적
  void trackWalletConnectionSuccess({
    required String walletType,
    required String address,
    int? chainId,
    String? cluster,
  }) {
    addBreadcrumb(
      message: 'Wallet connection successful',
      category: 'wallet.connection',
      data: {
        'wallet_type': walletType,
        'address': _maskAddress(address),
        if (chainId != null) 'chain_id': chainId,
        if (cluster != null) 'cluster': cluster,
      },
      level: SentryLevel.info,
    );

    // 지갑 컨텍스트 설정
    setContext('wallet', {
      'type': walletType,
      'address': _maskAddress(address),
      if (chainId != null) 'chain_id': chainId,
      if (cluster != null) 'cluster': cluster,
    });
  }

  /// 지갑 연결 실패 추적
  Future<void> trackWalletConnectionFailure({
    required String walletType,
    required dynamic error,
    StackTrace? stackTrace,
    String? errorStep,
    int? chainId,
    String? cluster,
  }) async {
    addBreadcrumb(
      message: 'Wallet connection failed',
      category: 'wallet.connection',
      data: {
        'wallet_type': walletType,
        'error': error.toString(),
        if (errorStep != null) 'error_step': errorStep,
      },
      level: SentryLevel.error,
    );

    await captureException(
      error,
      stackTrace: stackTrace,
      tags: {
        'failed_wallet': walletType,
        'error_type': 'wallet_connection',
        if (chainId != null) 'chain_id': chainId.toString(),
      },
      extras: {
        'wallet_type': walletType,
        if (errorStep != null) 'error_step': errorStep,
        if (chainId != null) 'chain_id': chainId,
        if (cluster != null) 'cluster': cluster,
      },
      level: SentryLevel.error,
    );
  }

  /// 지갑 연결 해제 추적
  void trackWalletDisconnection({
    required String walletType,
    String? address,
    String? reason,
  }) {
    addBreadcrumb(
      message: 'Wallet disconnected',
      category: 'wallet.connection',
      data: {
        'wallet_type': walletType,
        if (address != null) 'address': _maskAddress(address),
        if (reason != null) 'reason': reason,
      },
    );

    // 지갑 컨텍스트 제거
    setContext('wallet', {});
  }

  /// 트랜잭션 서명 시작 추적
  void trackSignatureStart({
    required String type,
    String? walletType,
    int? chainId,
  }) {
    addBreadcrumb(
      message: 'Signature request started',
      category: 'wallet.signature',
      data: {
        'type': type,
        if (walletType != null) 'wallet_type': walletType,
        if (chainId != null) 'chain_id': chainId,
      },
    );
  }

  /// 트랜잭션 서명 실패 추적
  Future<void> trackSignatureFailure({
    required String type,
    required dynamic error,
    StackTrace? stackTrace,
    String? walletType,
    int? chainId,
  }) async {
    addBreadcrumb(
      message: 'Signature request failed',
      category: 'wallet.signature',
      data: {
        'type': type,
        'error': error.toString(),
      },
      level: SentryLevel.error,
    );

    await captureException(
      error,
      stackTrace: stackTrace,
      tags: {
        'error_type': 'signature_failure',
        'signature_type': type,
        if (walletType != null) 'wallet_type': walletType,
      },
      extras: {
        'signature_type': type,
        if (chainId != null) 'chain_id': chainId,
      },
      level: SentryLevel.error,
    );
  }

  /// 체인 전환 추적
  void trackChainSwitch({
    required int fromChainId,
    required int toChainId,
    bool success = true,
    String? error,
  }) {
    addBreadcrumb(
      message: success ? 'Chain switch successful' : 'Chain switch failed',
      category: 'wallet.chain',
      data: {
        'from_chain_id': fromChainId,
        'to_chain_id': toChainId,
        if (error != null) 'error': error,
      },
      level: success ? SentryLevel.info : SentryLevel.error,
    );

    if (success) {
      setTag('chain_id', toChainId.toString());
    }
  }

  /// 딥링크 처리 추적
  void trackDeepLink({
    required String scheme,
    required String host,
    String? path,
    bool success = true,
    String? error,
  }) {
    addBreadcrumb(
      message: success ? 'Deep link processed' : 'Deep link failed',
      category: 'deeplink',
      data: {
        'scheme': scheme,
        'host': host,
        if (path != null) 'path': path,
        if (error != null) 'error': error,
      },
      level: success ? SentryLevel.info : SentryLevel.warning,
    );
  }

  // ============================================================================
  // Device Context (디바이스 정보)
  // ============================================================================

  /// 디바이스 정보 설정
  void setDeviceContext() {
    if (!_isInitialized) return;

    setContext('device_info', {
      'platform': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'dart_version': Platform.version,
      'locale': Platform.localeName,
    });
  }

  // ============================================================================
  // Performance Monitoring (성능 모니터링)
  // ============================================================================

  /// 트랜잭션 시작 (성능 모니터링)
  ISentrySpan? startTransaction({
    required String name,
    required String operation,
  }) {
    if (!_isInitialized) return null;

    return Sentry.startTransaction(
      name,
      operation,
      bindToScope: true,
    );
  }

  // ============================================================================
  // Utility Methods
  // ============================================================================

  /// 주소 마스킹 (개인정보 보호)
  String _maskAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// 모든 스코프 초기화
  void clearScope() {
    if (!_isInitialized) return;

    Sentry.configureScope((scope) {
      scope.clear();
    });
  }

  // ============================================================================
  // Debug Logging (디버그 로깅)
  // ============================================================================

  /// Sentry 이벤트를 콘솔에 출력 (Debug 모드 전용)
  ///
  /// beforeSend 콜백에서 호출되어 Sentry로 전송되는 이벤트를
  /// IDE 콘솔에서 즉시 확인할 수 있게 합니다.
  static void _printEventToConsole(SentryEvent event) {
    final exception = event.exceptions?.firstOrNull;
    final exceptionType = exception?.type ?? 'Event';
    final exceptionValue = exception?.value ?? event.message?.formatted ?? 'No message';

    // 메인 에러 정보 출력
    // ignore: avoid_print
    print('🚨 [Sentry] $exceptionType: $exceptionValue');

    // 지갑 컨텍스트가 있으면 추가 출력
    if (event.contexts['wallet'] != null) {
      // ignore: avoid_print
      print('   📱 Wallet: ${event.contexts['wallet']}');
    }

    // 태그가 있으면 출력
    if (event.tags != null && event.tags!.isNotEmpty) {
      // ignore: avoid_print
      print('   🏷️ Tags: ${event.tags}');
    }
  }

}
