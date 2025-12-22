import 'dart:async';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry 이벤트 정보를 저장하는 데이터 클래스
///
/// beforeSend 콜백에서 인터셉트된 Sentry 이벤트를 로컬에서 확인하기 위해 사용됩니다.
class DebugLogEntry {
  final String id;
  final DateTime timestamp;
  final String level;
  final String? exceptionType;
  final String? exceptionValue;
  final String? culprit;
  final Map<String, dynamic>? tags;
  final Map<String, dynamic>? contexts;
  final List<String>? breadcrumbs;

  DebugLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    this.exceptionType,
    this.exceptionValue,
    this.culprit,
    this.tags,
    this.contexts,
    this.breadcrumbs,
  });

  /// SentryEvent에서 DebugLogEntry 생성
  factory DebugLogEntry.fromSentryEvent(SentryEvent event) {
    final exception = event.exceptions?.firstOrNull;

    // contexts를 안전하게 Map<String, dynamic>으로 변환
    Map<String, dynamic>? contextsMap;
    if (event.contexts.isNotEmpty) {
      contextsMap = {};
      event.contexts.forEach((key, value) {
        if (value != null) {
          contextsMap![key] = value.toString();
        }
      });
    }

    // breadcrumbs를 문자열 리스트로 변환
    List<String>? breadcrumbsList;
    if (event.breadcrumbs != null && event.breadcrumbs!.isNotEmpty) {
      breadcrumbsList = event.breadcrumbs!
          .map((b) => '[${b.category ?? 'unknown'}] ${b.message ?? ''}')
          .toList();
    }

    return DebugLogEntry(
      id: event.eventId.toString(),
      timestamp: event.timestamp ?? DateTime.now(),
      level: event.level?.name ?? 'unknown',
      exceptionType: exception?.type,
      exceptionValue: exception?.value,
      culprit: event.culprit,
      tags: event.tags,
      contexts: contextsMap,
      breadcrumbs: breadcrumbsList,
    );
  }

  @override
  String toString() {
    return 'DebugLogEntry(id: $id, level: $level, type: $exceptionType, value: $exceptionValue)';
  }
}

/// 디버그용 Sentry 로그 저장소 서비스
///
/// beforeSend 콜백에서 인터셉트된 Sentry 이벤트를 메모리에 저장합니다.
/// Debug 모드에서만 사용되며, 프로덕션에서는 비활성화됩니다.
///
/// 사용 예시:
/// ```dart
/// // 로그 목록 조회
/// final logs = DebugLogService.instance.logs;
///
/// // 스트림으로 실시간 업데이트 수신
/// DebugLogService.instance.logStream.listen((logs) {
///   print('New log count: ${logs.length}');
/// });
/// ```
class DebugLogService {
  DebugLogService._();
  static final DebugLogService instance = DebugLogService._();

  final List<DebugLogEntry> _logs = [];
  final _logController = StreamController<List<DebugLogEntry>>.broadcast();

  /// 메모리 관리를 위한 최대 로그 수
  static const int maxLogs = 100;

  /// 로그 추가 (beforeSend에서 호출)
  ///
  /// 최대 로그 수를 초과하면 가장 오래된 로그부터 삭제합니다.
  void addLog(DebugLogEntry entry) {
    _logs.add(entry);

    // 메모리 관리: 최대 개수 초과 시 오래된 것부터 삭제
    while (_logs.length > maxLogs) {
      _logs.removeAt(0);
    }

    // 스트림으로 업데이트 알림
    _logController.add(List.unmodifiable(_logs));
  }

  /// 현재 저장된 로그 목록 (최신순)
  List<DebugLogEntry> get logs => List.unmodifiable(_logs.reversed.toList());

  /// 로그 스트림 (실시간 업데이트)
  Stream<List<DebugLogEntry>> get logStream => _logController.stream;

  /// 저장된 로그 개수
  int get logCount => _logs.length;

  /// 모든 로그 초기화
  void clear() {
    _logs.clear();
    _logController.add([]);
  }

  /// 특정 레벨의 로그만 필터링
  List<DebugLogEntry> getLogsByLevel(String level) {
    return _logs.where((log) => log.level == level).toList().reversed.toList();
  }

  // ============================================================================
  // Wallet-Specific Log Storage
  // ============================================================================

  final List<DebugLogEntry> _walletLogs = [];
  final _walletLogController = StreamController<List<DebugLogEntry>>.broadcast();

  /// Maximum wallet logs to keep in memory
  static const int maxWalletLogs = 200;

  /// Add a wallet-specific log entry
  ///
  /// Wallet logs are stored separately for easier filtering and analysis.
  void addWalletLog(DebugLogEntry entry) {
    _walletLogs.add(entry);

    // Memory management: FIFO eviction when full
    while (_walletLogs.length > maxWalletLogs) {
      _walletLogs.removeAt(0);
    }

    // Notify listeners
    _walletLogController.add(List.unmodifiable(_walletLogs));
  }

  /// Current wallet logs (newest first)
  List<DebugLogEntry> get walletLogs =>
      List.unmodifiable(_walletLogs.reversed.toList());

  /// Wallet log stream for real-time updates
  Stream<List<DebugLogEntry>> get walletLogStream => _walletLogController.stream;

  /// Number of stored wallet logs
  int get walletLogCount => _walletLogs.length;

  /// Filter wallet logs by connection ID
  ///
  /// Returns logs for a specific connection attempt.
  List<DebugLogEntry> getWalletLogsByConnectionId(String connectionId) {
    return _walletLogs
        .where((log) {
          // Check if the log has connectionId in its context
          if (log.contexts != null && log.contexts!['connectionId'] == connectionId) {
            return true;
          }
          // For WalletDebugLogEntry subclass, check the connectionId field
          if (log.id.startsWith(connectionId)) {
            return true;
          }
          return false;
        })
        .toList()
        .reversed
        .toList();
  }

  /// Filter wallet logs by wallet type
  List<DebugLogEntry> getWalletLogsByType(String walletType) {
    return _walletLogs
        .where((log) {
          if (log.contexts != null && log.contexts!['walletType'] == walletType) {
            return true;
          }
          return log.id.contains(walletType);
        })
        .toList()
        .reversed
        .toList();
  }

  /// Clear wallet logs only
  void clearWalletLogs() {
    _walletLogs.clear();
    _walletLogController.add([]);
  }

  /// 리소스 정리
  void dispose() {
    _logController.close();
    _walletLogController.close();
  }
}
