import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';

/// DebugLogService 인스턴스 Provider
///
/// 싱글톤 DebugLogService에 접근하기 위한 Provider입니다.
/// Debug 모드에서 Sentry 로그를 확인할 때 사용합니다.
///
/// 사용 예시:
/// ```dart
/// final service = ref.read(debugLogServiceProvider);
/// service.clear(); // 로그 초기화
/// ```
final debugLogServiceProvider = Provider<DebugLogService>((ref) {
  return DebugLogService.instance;
});

/// 디버그 로그 스트림 Provider
///
/// Sentry 로그가 추가될 때마다 실시간으로 업데이트됩니다.
/// UI에서 로그 목록을 실시간으로 표시할 때 사용합니다.
///
/// 사용 예시:
/// ```dart
/// final logsAsync = ref.watch(debugLogStreamProvider);
/// logsAsync.when(
///   data: (logs) => ListView.builder(...),
///   loading: () => CircularProgressIndicator(),
///   error: (e, st) => Text('Error: $e'),
/// );
/// ```
final debugLogStreamProvider = StreamProvider<List<DebugLogEntry>>((ref) {
  return DebugLogService.instance.logStream;
});

/// 현재 디버그 로그 목록 Provider
///
/// 현재 저장된 로그 목록을 즉시 가져옵니다 (최신순 정렬).
/// 스트림이 필요 없는 경우 사용합니다.
///
/// 사용 예시:
/// ```dart
/// final logs = ref.watch(debugLogsProvider);
/// for (final log in logs) {
///   print('${log.timestamp}: ${log.exceptionType}');
/// }
/// ```
final debugLogsProvider = Provider<List<DebugLogEntry>>((ref) {
  return DebugLogService.instance.logs;
});

/// 디버그 로그 개수 Provider
///
/// 현재 저장된 로그 개수를 반환합니다.
/// 배지나 카운터 표시에 유용합니다.
final debugLogCountProvider = Provider<int>((ref) {
  return DebugLogService.instance.logCount;
});
