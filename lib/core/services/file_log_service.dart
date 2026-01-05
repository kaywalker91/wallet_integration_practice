import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// File-based logging service for debugging session restoration issues.
///
/// Logs persist across app restarts, allowing analysis of cold start scenarios.
/// Use this for debugging wallet connection and session restoration flows.
class FileLogService {
  FileLogService._();

  static final FileLogService instance = FileLogService._();

  File? _logFile;
  bool _initialized = false;

  static const String _logFileName = 'wallet_session_debug.log';
  static const int _maxLogSizeBytes = 1024 * 1024; // 1MB max

  /// Initialize the file log service.
  /// Must be called before using any logging methods.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$_logFileName');

      // Rotate log if too large
      if (await _logFile!.exists()) {
        final stat = await _logFile!.stat();
        if (stat.size > _maxLogSizeBytes) {
          await _rotateLog();
        }
      }

      _initialized = true;

      // Log initialization
      await log('INIT', 'FileLogService initialized', {
        'path': _logFile!.path,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Silently fail - don't crash app for logging issues
      _initialized = false;
    }
  }

  /// Log a message with tag and optional data.
  ///
  /// [tag] - Category tag (e.g., 'RESTORE', 'SDK', 'RELAY')
  /// [message] - Log message
  /// [data] - Optional structured data
  Future<void> log(
    String tag,
    String message, [
    Map<String, dynamic>? data,
  ]) async {
    if (!_initialized || _logFile == null) return;

    try {
      final timestamp = DateTime.now().toIso8601String();
      final dataStr = data != null ? ' | $data' : '';
      final line = '[$timestamp][$tag] $message$dataStr\n';

      await _logFile!.writeAsString(line, mode: FileMode.append);
    } catch (e) {
      // Silently fail
    }
  }

  /// Log session restoration event
  Future<void> logRestore(String message, [Map<String, dynamic>? data]) async {
    await log('RESTORE', message, data);
  }

  /// Log SDK-related event
  Future<void> logSdk(String message, [Map<String, dynamic>? data]) async {
    await log('SDK', message, data);
  }

  /// Log relay connection event
  Future<void> logRelay(String message, [Map<String, dynamic>? data]) async {
    await log('RELAY', message, data);
  }

  /// Log MetaMask-specific event
  Future<void> logMetaMask(String message, [Map<String, dynamic>? data]) async {
    await log('METAMASK', message, data);
  }

  /// Log validation event
  Future<void> logValidation(
    String message, [
    Map<String, dynamic>? data,
  ]) async {
    await log('VALIDATE', message, data);
  }

  /// Log error
  Future<void> logError(
    String message,
    Object? error, [
    StackTrace? stackTrace,
  ]) async {
    await log('ERROR', message, {
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString().split('\n').take(5).join('\n'),
    });
  }

  /// Read all logs from file.
  Future<String> readLogs() async {
    if (!_initialized || _logFile == null) {
      return 'FileLogService not initialized';
    }

    try {
      if (await _logFile!.exists()) {
        return await _logFile!.readAsString();
      }
      return 'No logs found';
    } catch (e) {
      return 'Error reading logs: $e';
    }
  }

  /// Get recent logs (last N lines).
  Future<String> getRecentLogs({int lines = 100}) async {
    final allLogs = await readLogs();
    final logLines = allLogs.split('\n');

    if (logLines.length <= lines) {
      return allLogs;
    }

    return logLines.skip(logLines.length - lines).join('\n');
  }

  /// Clear all logs.
  Future<void> clearLogs() async {
    if (!_initialized || _logFile == null) return;

    try {
      await _logFile!.writeAsString('');
      await log('INIT', 'Logs cleared');
    } catch (e) {
      // Silently fail
    }
  }

  /// Get log file path for sharing.
  String? getLogFilePath() {
    return _logFile?.path;
  }

  /// Rotate log file when it exceeds max size.
  Future<void> _rotateLog() async {
    if (_logFile == null) return;

    try {
      final backupPath = '${_logFile!.path}.old';
      final backupFile = File(backupPath);

      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      await _logFile!.rename(backupPath);
      _logFile = File('${(await getApplicationDocumentsDirectory()).path}/$_logFileName');
    } catch (e) {
      // If rotation fails, just clear the log
      await _logFile!.writeAsString('');
    }
  }

  /// Add a separator line for readability.
  Future<void> logSeparator([String? label]) async {
    final sep = label != null
        ? '\n========== $label ==========\n'
        : '\n================================\n';
    await log('---', sep);
  }
}
