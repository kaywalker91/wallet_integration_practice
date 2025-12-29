import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_integration_practice/core/utils/exponential_backoff.dart';

void main() {
  group('ExponentialBackoff', () {
    test('has correct default values', () {
      final backoff = ExponentialBackoff();

      expect(backoff.initialDelay, const Duration(milliseconds: 500));
      expect(backoff.maxDelay, const Duration(seconds: 30));
      expect(backoff.multiplier, 2.0);
      expect(backoff.jitterFactor, 0.1);
      expect(backoff.maxRetries, 5);
      expect(backoff.currentRetry, 0);
      expect(backoff.hasMoreRetries, true);
    });

    test('custom values are set correctly', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(seconds: 1),
        maxDelay: const Duration(minutes: 1),
        multiplier: 3.0,
        jitterFactor: 0.2,
        maxRetries: 10,
      );

      expect(backoff.initialDelay, const Duration(seconds: 1));
      expect(backoff.maxDelay, const Duration(minutes: 1));
      expect(backoff.multiplier, 3.0);
      expect(backoff.jitterFactor, 0.2);
      expect(backoff.maxRetries, 10);
    });

    test('currentDelay increases exponentially', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(milliseconds: 100),
        multiplier: 2.0,
        jitterFactor: 0.0, // No jitter for predictable testing
        maxDelay: const Duration(seconds: 10),
      );

      // Retry 0: 100ms
      expect(backoff.currentDelay.inMilliseconds, 100);

      backoff.incrementRetry();
      // Retry 1: 200ms
      expect(backoff.currentDelay.inMilliseconds, 200);

      backoff.incrementRetry();
      // Retry 2: 400ms
      expect(backoff.currentDelay.inMilliseconds, 400);

      backoff.incrementRetry();
      // Retry 3: 800ms
      expect(backoff.currentDelay.inMilliseconds, 800);
    });

    test('currentDelay is capped at maxDelay', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(seconds: 1),
        multiplier: 2.0,
        jitterFactor: 0.0,
        maxDelay: const Duration(seconds: 5),
        maxRetries: 10,
      );

      // Simulate multiple retries
      for (var i = 0; i < 5; i++) {
        backoff.incrementRetry();
      }

      // After 5 retries: 1 * 2^5 = 32 seconds, but capped at 5s
      expect(backoff.currentDelay.inMilliseconds, lessThanOrEqualTo(5000));
    });

    test('jitter adds randomness to delay', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(seconds: 1),
        multiplier: 2.0,
        jitterFactor: 0.5, // 50% jitter
        maxDelay: const Duration(seconds: 30),
      );

      // Collect multiple delay samples
      final delays = <int>[];
      for (var i = 0; i < 10; i++) {
        delays.add(backoff.currentDelay.inMilliseconds);
      }

      // With jitter, delays should vary
      // Base delay is 1000ms, with 50% jitter it should be between 500-1500ms
      for (final delay in delays) {
        expect(delay, greaterThanOrEqualTo(500));
        expect(delay, lessThanOrEqualTo(1500));
      }
    });

    test('getDelayForRetry calculates correct delay for specific retry', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(milliseconds: 100),
        multiplier: 2.0,
        jitterFactor: 0.0,
        maxDelay: const Duration(seconds: 10),
      );

      expect(backoff.getDelayForRetry(0).inMilliseconds, 100);
      expect(backoff.getDelayForRetry(1).inMilliseconds, 200);
      expect(backoff.getDelayForRetry(2).inMilliseconds, 400);
      expect(backoff.getDelayForRetry(3).inMilliseconds, 800);
    });

    test('incrementRetry increases currentRetry', () {
      final backoff = ExponentialBackoff();

      expect(backoff.currentRetry, 0);

      backoff.incrementRetry();
      expect(backoff.currentRetry, 1);

      backoff.incrementRetry();
      expect(backoff.currentRetry, 2);
    });

    test('hasMoreRetries returns false when max retries reached', () {
      final backoff = ExponentialBackoff(maxRetries: 3);

      expect(backoff.hasMoreRetries, true);

      backoff.incrementRetry();
      backoff.incrementRetry();
      backoff.incrementRetry();

      expect(backoff.hasMoreRetries, false);
    });

    test('reset resets currentRetry to 0', () {
      final backoff = ExponentialBackoff();

      backoff.incrementRetry();
      backoff.incrementRetry();
      expect(backoff.currentRetry, 2);

      backoff.reset();
      expect(backoff.currentRetry, 0);
    });

    group('execute', () {
      test('returns result on success', () async {
        final backoff = ExponentialBackoff();

        final result = await backoff.execute(() async => 'success');

        expect(result, 'success');
        expect(backoff.currentRetry, 0);
      });

      test('retries on failure and eventually succeeds', () async {
        final backoff = ExponentialBackoff(
          initialDelay: const Duration(milliseconds: 10),
          maxRetries: 5,
        );

        var attempts = 0;
        final result = await backoff.execute(() async {
          attempts++;
          if (attempts < 3) {
            throw Exception('Temporary error');
          }
          return 'success after retries';
        });

        expect(result, 'success after retries');
        expect(attempts, 3);
      });

      test('throws after max retries exceeded', () async {
        final backoff = ExponentialBackoff(
          initialDelay: const Duration(milliseconds: 10),
          maxRetries: 2,
        );

        await expectLater(
          backoff.execute(() async {
            throw Exception('Persistent error');
          }),
          throwsA(isA<Exception>()),
        );
      });

      test('respects shouldRetry predicate', () async {
        final backoff = ExponentialBackoff(
          initialDelay: const Duration(milliseconds: 10),
          maxRetries: 5,
        );

        var attempts = 0;
        await expectLater(
          backoff.execute(
            () async {
              attempts++;
              throw const FormatException('Non-retryable');
            },
            shouldRetry: (error) => error is! FormatException,
          ),
          throwsA(isA<FormatException>()),
        );

        expect(attempts, 1); // Should not retry
      });

      test('calls onRetry callback', () async {
        final backoff = ExponentialBackoff(
          initialDelay: const Duration(milliseconds: 10),
          maxRetries: 5,
        );

        final retryCalls = <int>[];
        var attempts = 0;

        await backoff.execute(
          () async {
            attempts++;
            if (attempts < 3) {
              throw Exception('Temporary');
            }
            return 'done';
          },
          onRetry: (attempt, delay, error) {
            retryCalls.add(attempt);
          },
        );

        expect(retryCalls, [1, 2]);
      });
    });
  });

  group('CircuitBreaker', () {
    test('has correct default values', () {
      final breaker = CircuitBreaker();

      expect(breaker.failureThreshold, 5);
      expect(breaker.resetTimeout, const Duration(seconds: 60));
      expect(breaker.halfOpenSuccessThreshold, 2);
      expect(breaker.state, CircuitState.closed);
      expect(breaker.isAllowed, true);
    });

    test('custom values are set correctly', () {
      final breaker = CircuitBreaker(
        failureThreshold: 10,
        resetTimeout: const Duration(seconds: 30),
        halfOpenSuccessThreshold: 3,
      );

      expect(breaker.failureThreshold, 10);
      expect(breaker.resetTimeout, const Duration(seconds: 30));
      expect(breaker.halfOpenSuccessThreshold, 3);
    });

    test('opens after failure threshold reached', () {
      final breaker = CircuitBreaker(failureThreshold: 3);

      expect(breaker.state, CircuitState.closed);

      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.state, CircuitState.closed);

      breaker.recordFailure();
      expect(breaker.state, CircuitState.open);
      expect(breaker.isAllowed, false);
    });

    test('success resets failure count in closed state', () {
      final breaker = CircuitBreaker(failureThreshold: 3);

      breaker.recordFailure();
      breaker.recordFailure();
      breaker.recordSuccess();

      // Failure count should be reset
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.state, CircuitState.closed);
    });

    test('transitions to half-open after reset timeout', () async {
      final breaker = CircuitBreaker(
        failureThreshold: 2,
        resetTimeout: const Duration(milliseconds: 50),
      );

      // Open the circuit
      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.state, CircuitState.open);

      // Wait for reset timeout
      await Future.delayed(const Duration(milliseconds: 60));

      // Check isAllowed triggers timeout check
      expect(breaker.isAllowed, true);
      expect(breaker.state, CircuitState.halfOpen);
    });

    test('closes from half-open after success threshold', () async {
      final breaker = CircuitBreaker(
        failureThreshold: 2,
        resetTimeout: const Duration(milliseconds: 10),
        halfOpenSuccessThreshold: 2,
      );

      // Open the circuit
      breaker.recordFailure();
      breaker.recordFailure();

      // Wait for half-open
      await Future.delayed(const Duration(milliseconds: 20));
      expect(breaker.isAllowed, true);
      expect(breaker.state, CircuitState.halfOpen);

      // Successful calls
      breaker.recordSuccess();
      expect(breaker.state, CircuitState.halfOpen);

      breaker.recordSuccess();
      expect(breaker.state, CircuitState.closed);
    });

    test('returns to open from half-open on failure', () async {
      final breaker = CircuitBreaker(
        failureThreshold: 2,
        resetTimeout: const Duration(milliseconds: 10),
      );

      // Open the circuit
      breaker.recordFailure();
      breaker.recordFailure();

      // Wait for half-open
      await Future.delayed(const Duration(milliseconds: 20));
      expect(breaker.isAllowed, true);
      expect(breaker.state, CircuitState.halfOpen);

      // Failure in half-open
      breaker.recordFailure();
      expect(breaker.state, CircuitState.open);
    });

    test('reset resets all state', () {
      final breaker = CircuitBreaker(failureThreshold: 2);

      breaker.recordFailure();
      breaker.recordFailure();
      expect(breaker.state, CircuitState.open);

      breaker.reset();
      expect(breaker.state, CircuitState.closed);
      expect(breaker.isAllowed, true);
    });

    group('execute', () {
      test('returns result when circuit is closed', () async {
        final breaker = CircuitBreaker();

        final result = await breaker.execute(() async => 'success');

        expect(result, 'success');
      });

      test('throws CircuitBreakerOpenException when open', () async {
        final breaker = CircuitBreaker(failureThreshold: 2);

        // Open the circuit
        breaker.recordFailure();
        breaker.recordFailure();

        await expectLater(
          breaker.execute(() async => 'never reached'),
          throwsA(isA<CircuitBreakerOpenException>()),
        );
      });

      test('records success on successful execution', () async {
        final breaker = CircuitBreaker(failureThreshold: 3);

        breaker.recordFailure();
        breaker.recordFailure();

        await breaker.execute(() async => 'success');

        // Failure count should be reset
        breaker.recordFailure();
        breaker.recordFailure();
        expect(breaker.state, CircuitState.closed);
      });

      test('records failure on failed execution', () async {
        final breaker = CircuitBreaker(failureThreshold: 2);

        try {
          await breaker.execute(() async {
            throw Exception('Error');
          });
        } catch (_) {}

        try {
          await breaker.execute(() async {
            throw Exception('Error');
          });
        } catch (_) {}

        expect(breaker.state, CircuitState.open);
      });

      test('rethrows original exception', () async {
        final breaker = CircuitBreaker();
        const testException = FormatException('Test error');

        await expectLater(
          breaker.execute(() async => throw testException),
          throwsA(equals(testException)),
        );
      });
    });
  });

  group('CircuitBreakerOpenException', () {
    test('has correct message', () {
      final exception = CircuitBreakerOpenException('Test message');

      expect(exception.message, 'Test message');
      expect(
        exception.toString(),
        'CircuitBreakerOpenException: Test message',
      );
    });
  });
}
