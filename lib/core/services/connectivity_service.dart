import 'dart:async';
import 'dart:io';

import 'package:wallet_integration_practice/core/utils/logger.dart';

/// Network connectivity status
enum ConnectivityStatus {
  /// Device is online with network access
  online,

  /// Device appears offline or no network access
  offline,

  /// Connectivity status is unknown (initial state)
  unknown,
}

/// Service for checking and monitoring network connectivity
///
/// Provides both one-time checks and stream-based monitoring for
/// network connectivity changes.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final StreamController<ConnectivityStatus> _statusController =
      StreamController<ConnectivityStatus>.broadcast();

  ConnectivityStatus _currentStatus = ConnectivityStatus.unknown;
  Timer? _pollingTimer;
  bool _isMonitoring = false;

  /// Current connectivity status
  ConnectivityStatus get currentStatus => _currentStatus;

  /// Stream of connectivity status changes
  Stream<ConnectivityStatus> get statusStream => _statusController.stream;

  /// Whether device is currently online
  bool get isOnline => _currentStatus == ConnectivityStatus.online;

  /// Whether device is currently offline
  bool get isOffline => _currentStatus == ConnectivityStatus.offline;

  /// Check current network connectivity
  ///
  /// Performs a DNS lookup to verify actual internet connectivity,
  /// not just network interface availability.
  Future<ConnectivityStatus> checkConnectivity() async {
    try {
      // Try to resolve a reliable DNS host
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _updateStatus(ConnectivityStatus.online);
        return ConnectivityStatus.online;
      }
    } on SocketException catch (_) {
      AppLogger.d('Connectivity check: Socket exception (offline)');
    } on TimeoutException catch (_) {
      AppLogger.d('Connectivity check: Timeout (offline)');
    } catch (e) {
      AppLogger.d('Connectivity check: Error - $e');
    }

    _updateStatus(ConnectivityStatus.offline);
    return ConnectivityStatus.offline;
  }

  /// Start monitoring connectivity with periodic checks
  ///
  /// [interval] - How often to check connectivity (default: 10 seconds)
  void startMonitoring({Duration interval = const Duration(seconds: 10)}) {
    if (_isMonitoring) return;

    _isMonitoring = true;
    AppLogger.d('Connectivity monitoring started (interval: ${interval.inSeconds}s)');

    // Initial check
    checkConnectivity();

    // Set up periodic polling
    _pollingTimer = Timer.periodic(interval, (_) {
      checkConnectivity();
    });
  }

  /// Stop monitoring connectivity
  void stopMonitoring() {
    _isMonitoring = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    AppLogger.d('Connectivity monitoring stopped');
  }

  /// Wait for connectivity to be restored
  ///
  /// Returns immediately if already online.
  /// [timeout] - Maximum time to wait (default: 30 seconds)
  Future<bool> waitForConnectivity({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Check current status first
    final currentCheck = await checkConnectivity();
    if (currentCheck == ConnectivityStatus.online) {
      return true;
    }

    // Start monitoring if not already
    final wasMonitoring = _isMonitoring;
    if (!wasMonitoring) {
      startMonitoring(interval: const Duration(seconds: 2));
    }

    try {
      // Wait for online status or timeout
      await statusStream
          .firstWhere((status) => status == ConnectivityStatus.online)
          .timeout(timeout);
      return true;
    } on TimeoutException {
      AppLogger.d('Wait for connectivity timed out');
      return false;
    } finally {
      // Restore previous monitoring state
      if (!wasMonitoring) {
        stopMonitoring();
      }
    }
  }

  void _updateStatus(ConnectivityStatus newStatus) {
    if (_currentStatus != newStatus) {
      AppLogger.d('Connectivity status changed: $_currentStatus -> $newStatus');
      _currentStatus = newStatus;
      _statusController.add(newStatus);
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}
