import 'package:logger/logger.dart';

/// Application logger utility
class AppLogger {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static final Logger _loggerNoStack = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// Log debug message
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _loggerNoStack.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log info message
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _loggerNoStack.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warning message
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log error message
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log wallet-specific events
  static void wallet(String event, {Map<String, dynamic>? data}) {
    final buffer = StringBuffer('[WALLET] $event');
    if (data != null) {
      buffer.write(' | $data');
    }
    _loggerNoStack.i(buffer.toString());
  }

  /// Log transaction events
  static void tx(String event, {String? txHash, Map<String, dynamic>? data}) {
    final buffer = StringBuffer('[TX] $event');
    if (txHash != null) {
      buffer.write(' | hash: $txHash');
    }
    if (data != null) {
      buffer.write(' | $data');
    }
    _loggerNoStack.i(buffer.toString());
  }
}
