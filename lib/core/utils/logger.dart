import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Application logger utility with production-aware log levels.
///
/// In debug mode: All log levels (debug, info, warning, error) are printed.
/// In production: Only warning and error levels are printed to reduce noise
/// and protect potentially sensitive debug information.
class AppLogger {
  /// Production-safe logger that only logs warnings and errors
  static final Logger _productionLogger = Logger(
    level: Level.warning,
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// Development logger with all levels enabled
  static final Logger _debugLogger = Logger(
    level: Level.debug,
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// No-stack logger for cleaner output (debug mode only)
  static final Logger _debugLoggerNoStack = Logger(
    level: Level.debug,
    printer: PrettyPrinter(
      methodCount: 0,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// Get appropriate logger based on build mode (warnings/errors)
  static Logger get _logger => kDebugMode ? _debugLogger : _productionLogger;

  /// Log debug message (DEBUG MODE ONLY)
  ///
  /// These logs are suppressed in production to:
  /// - Reduce log noise
  /// - Prevent sensitive debug info from appearing in production logs
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _debugLoggerNoStack.d(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log info message (DEBUG MODE ONLY)
  ///
  /// Info-level logs are suppressed in production.
  /// Use [w] for important operational messages that should appear in production.
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      _debugLoggerNoStack.i(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Log warning message (ALWAYS LOGGED)
  ///
  /// Warnings are logged in both debug and production modes.
  /// Use for recoverable issues or important operational notices.
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message (ALWAYS LOGGED)
  ///
  /// Errors are always logged in both debug and production modes.
  /// Use for exceptions and critical failures.
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log wallet-specific events (DEBUG MODE ONLY)
  ///
  /// Wallet events contain potentially sensitive information (addresses, chains)
  /// and are suppressed in production. Errors should be logged via [e] instead.
  static void wallet(String event, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      final buffer = StringBuffer('[WALLET] $event');
      if (data != null) {
        // Mask sensitive data in logs
        final maskedData = _maskSensitiveData(data);
        buffer.write(' | $maskedData');
      }
      _debugLoggerNoStack.i(buffer.toString());
    }
  }

  /// Log transaction events (DEBUG MODE ONLY)
  ///
  /// Transaction logs may contain sensitive hashes and are suppressed in production.
  static void tx(String event, {String? txHash, Map<String, dynamic>? data}) {
    if (kDebugMode) {
      final buffer = StringBuffer('[TX] $event');
      if (txHash != null) {
        buffer.write(' | hash: ${_maskHash(txHash)}');
      }
      if (data != null) {
        final maskedData = _maskSensitiveData(data);
        buffer.write(' | $maskedData');
      }
      _debugLoggerNoStack.i(buffer.toString());
    }
  }

  /// Log session restoration events (DEBUG MODE ONLY)
  ///
  /// Session restoration logs are for debugging cold-start behavior.
  static void session(String event, {Map<String, dynamic>? data}) {
    if (kDebugMode) {
      final buffer = StringBuffer('[SESSION] $event');
      if (data != null) {
        final maskedData = _maskSensitiveData(data);
        buffer.write(' | $maskedData');
      }
      _debugLoggerNoStack.i(buffer.toString());
    }
  }

  /// Mask sensitive data in log output
  static Map<String, dynamic> _maskSensitiveData(Map<String, dynamic> data) {
    final masked = <String, dynamic>{};
    for (final entry in data.entries) {
      if (_isSensitiveKey(entry.key)) {
        if (entry.value is String) {
          masked[entry.key] = _maskString(entry.value as String);
        } else {
          masked[entry.key] = '***';
        }
      } else {
        masked[entry.key] = entry.value;
      }
    }
    return masked;
  }

  /// Check if a key contains sensitive data
  static bool _isSensitiveKey(String key) {
    final sensitivePatterns = [
      'address',
      'key',
      'secret',
      'token',
      'hash',
      'signature',
      'private',
      'mnemonic',
      'seed',
      'password',
    ];
    final lowerKey = key.toLowerCase();
    return sensitivePatterns.any((pattern) => lowerKey.contains(pattern));
  }

  /// Mask a string value, showing only first and last few characters
  static String _maskString(String value) {
    if (value.length <= 10) return '***';
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  /// Mask transaction hash
  static String _maskHash(String hash) {
    if (hash.length <= 12) return hash;
    return '${hash.substring(0, 8)}...${hash.substring(hash.length - 4)}';
  }
}