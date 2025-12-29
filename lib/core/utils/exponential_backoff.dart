import 'dart:math';

/// Exponential backoff utility for retry logic
///
/// Implements exponential backoff with optional jitter to prevent
/// thundering herd problems in retry scenarios.
class ExponentialBackoff {
  ExponentialBackoff({
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitterFactor = 0.1,
    this.maxRetries = 5,
  });

  /// Initial delay for first retry
  final Duration initialDelay;

  /// Maximum delay cap
  final Duration maxDelay;

  /// Delay multiplier for each retry
  final double multiplier;

  /// Jitter factor (0.0 to 1.0) for randomization
  final double jitterFactor;

  /// Maximum number of retries
  final int maxRetries;

  final Random _random = Random();
  int _currentRetry = 0;

  /// Current retry attempt number (0-indexed)
  int get currentRetry => _currentRetry;

  /// Whether more retries are available
  bool get hasMoreRetries => _currentRetry < maxRetries;

  /// Calculate delay for the current retry attempt
  Duration get currentDelay {
    // Calculate base delay with exponential backoff
    final baseDelayMs = initialDelay.inMilliseconds * pow(multiplier, _currentRetry);

    // Cap at max delay
    final cappedDelayMs = min(baseDelayMs, maxDelay.inMilliseconds.toDouble());

    // Add jitter (+/- jitterFactor percentage)
    final jitter = (cappedDelayMs * jitterFactor * (_random.nextDouble() * 2 - 1)).round();
    final finalDelayMs = max(0, (cappedDelayMs + jitter).round());

    return Duration(milliseconds: finalDelayMs);
  }

  /// Get delay for a specific retry number
  Duration getDelayForRetry(int retryNumber) {
    final baseDelayMs = initialDelay.inMilliseconds * pow(multiplier, retryNumber);
    final cappedDelayMs = min(baseDelayMs, maxDelay.inMilliseconds.toDouble());
    final jitter = (cappedDelayMs * jitterFactor * (_random.nextDouble() * 2 - 1)).round();
    final finalDelayMs = max(0, (cappedDelayMs + jitter).round());
    return Duration(milliseconds: finalDelayMs);
  }

  /// Increment retry counter
  void incrementRetry() {
    _currentRetry++;
  }

  /// Reset the backoff state
  void reset() {
    _currentRetry = 0;
  }

  /// Execute with automatic retry using exponential backoff
  ///
  /// [operation] - The async operation to execute
  /// [shouldRetry] - Optional predicate to determine if error should trigger retry
  /// [onRetry] - Optional callback when retry occurs
  Future<T> execute<T>(
    Future<T> Function() operation, {
    bool Function(Object error)? shouldRetry,
    void Function(int attempt, Duration delay, Object error)? onRetry,
  }) async {
    reset();

    while (true) {
      try {
        return await operation();
      } catch (e) {
        // Check if we should retry
        final canRetry = shouldRetry?.call(e) ?? true;
        if (!canRetry || !hasMoreRetries) {
          rethrow;
        }

        final delay = currentDelay;
        onRetry?.call(_currentRetry + 1, delay, e);
        incrementRetry();

        await Future.delayed(delay);
      }
    }
  }
}

/// Circuit breaker for repeated failures
///
/// Prevents repeated calls to a failing service by "opening" the circuit
/// after a threshold of failures, and automatically "half-opens" after
/// a reset timeout to allow retry attempts.
class CircuitBreaker {
  CircuitBreaker({
    this.failureThreshold = 5,
    this.resetTimeout = const Duration(seconds: 60),
    this.halfOpenSuccessThreshold = 2,
  });

  /// Number of failures before opening circuit
  final int failureThreshold;

  /// Time before attempting to close circuit
  final Duration resetTimeout;

  /// Number of successes needed in half-open state to close circuit
  final int halfOpenSuccessThreshold;

  int _failureCount = 0;
  int _halfOpenSuccessCount = 0;
  CircuitState _state = CircuitState.closed;
  DateTime? _lastFailureTime;

  /// Current circuit state
  CircuitState get state => _state;

  /// Whether requests are allowed
  bool get isAllowed {
    _checkTimeout();
    return _state != CircuitState.open;
  }

  void _checkTimeout() {
    if (_state == CircuitState.open && _lastFailureTime != null) {
      if (DateTime.now().difference(_lastFailureTime!) >= resetTimeout) {
        _state = CircuitState.halfOpen;
        _halfOpenSuccessCount = 0;
      }
    }
  }

  /// Record a successful call
  void recordSuccess() {
    if (_state == CircuitState.halfOpen) {
      _halfOpenSuccessCount++;
      if (_halfOpenSuccessCount >= halfOpenSuccessThreshold) {
        _state = CircuitState.closed;
        _failureCount = 0;
      }
    } else if (_state == CircuitState.closed) {
      _failureCount = 0;
    }
  }

  /// Record a failed call
  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();

    if (_state == CircuitState.halfOpen) {
      _state = CircuitState.open;
      _halfOpenSuccessCount = 0;
    } else if (_failureCount >= failureThreshold) {
      _state = CircuitState.open;
    }
  }

  /// Execute with circuit breaker protection
  Future<T> execute<T>(Future<T> Function() operation) async {
    if (!isAllowed) {
      throw CircuitBreakerOpenException(
        'Circuit breaker is open. Retry after ${resetTimeout.inSeconds}s.',
      );
    }

    try {
      final result = await operation();
      recordSuccess();
      return result;
    } catch (e) {
      recordFailure();
      rethrow;
    }
  }

  /// Reset the circuit breaker
  void reset() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _halfOpenSuccessCount = 0;
    _lastFailureTime = null;
  }
}

/// Circuit breaker state
enum CircuitState {
  /// Circuit is closed, requests allowed
  closed,

  /// Circuit is open, requests blocked
  open,

  /// Circuit is half-open, limited requests allowed to test service
  halfOpen,
}

/// Exception thrown when circuit breaker is open
class CircuitBreakerOpenException implements Exception {
  CircuitBreakerOpenException(this.message);

  final String message;

  @override
  String toString() => 'CircuitBreakerOpenException: $message';
}
