/// WalletConnect v2 Session Topic Validator
///
/// Validates and sanitizes WalletConnect session topics to ensure
/// they conform to the expected format (64-character hex string).
class TopicValidator {
  TopicValidator._();

  /// WalletConnect v2 topic length (64 hex characters = 32 bytes)
  static const int _topicLength = 64;

  /// Regex pattern for valid hex string
  static final RegExp _hexPattern = RegExp(r'^[a-fA-F0-9]+$');

  /// Validates that a topic string has the correct format.
  ///
  /// A valid WalletConnect v2 topic is a 64-character hexadecimal string.
  ///
  /// Returns `true` if the topic is valid, `false` otherwise.
  static bool isValidFormat(String? topic) {
    if (topic == null || topic.isEmpty) return false;
    if (topic.length != _topicLength) return false;
    return _hexPattern.hasMatch(topic);
  }

  /// Checks if a topic is non-null and non-empty.
  ///
  /// This is a basic check that doesn't validate format.
  /// Use [isValidFormat] for complete validation.
  static bool isNonEmpty(String? topic) {
    return topic != null && topic.trim().isNotEmpty;
  }

  /// Sanitizes a topic string by trimming whitespace and converting to lowercase.
  ///
  /// Returns the sanitized topic if valid, `null` if invalid.
  ///
  /// Example:
  /// ```dart
  /// final topic = TopicValidator.sanitize('  ABC123...  ');
  /// // Returns 'abc123...' if valid format, null otherwise
  /// ```
  static String? sanitize(String? topic) {
    if (topic == null) return null;

    final trimmed = topic.trim().toLowerCase();

    if (!isValidFormat(trimmed)) {
      return null;
    }

    return trimmed;
  }

  /// Validates a topic and returns detailed error information.
  ///
  /// Returns a [TopicValidationResult] with validation status and error details.
  static TopicValidationResult validate(String? topic) {
    if (topic == null) {
      return TopicValidationResult.invalid(
        error: TopicValidationError.nullTopic,
        message: 'Topic is null',
      );
    }

    final trimmed = topic.trim();

    if (trimmed.isEmpty) {
      return TopicValidationResult.invalid(
        error: TopicValidationError.emptyTopic,
        message: 'Topic is empty',
      );
    }

    if (trimmed.length != _topicLength) {
      return TopicValidationResult.invalid(
        error: TopicValidationError.invalidLength,
        message: 'Topic length ${trimmed.length} != expected $_topicLength',
      );
    }

    if (!_hexPattern.hasMatch(trimmed)) {
      return TopicValidationResult.invalid(
        error: TopicValidationError.invalidCharacters,
        message: 'Topic contains non-hexadecimal characters',
      );
    }

    return TopicValidationResult.valid(topic: trimmed.toLowerCase());
  }

  /// Compares two topics for equality (case-insensitive).
  ///
  /// Returns `true` if both topics are valid and equal.
  static bool areEqual(String? topic1, String? topic2) {
    final sanitized1 = sanitize(topic1);
    final sanitized2 = sanitize(topic2);

    if (sanitized1 == null || sanitized2 == null) return false;

    return sanitized1 == sanitized2;
  }

  /// Masks a topic for safe logging (shows first and last 4 characters).
  ///
  /// Example: 'abc123...xyz789' becomes 'abc1...789'
  static String maskForLogging(String? topic) {
    if (topic == null || topic.length < 10) {
      return '***';
    }
    return '${topic.substring(0, 4)}...${topic.substring(topic.length - 4)}';
  }
}

/// Result of topic validation with detailed error information.
class TopicValidationResult {
  const TopicValidationResult._({
    required this.isValid,
    this.topic,
    this.error,
    this.message,
  });

  /// Creates a valid result with the sanitized topic.
  factory TopicValidationResult.valid({required String topic}) {
    return TopicValidationResult._(
      isValid: true,
      topic: topic,
    );
  }

  /// Creates an invalid result with error details.
  factory TopicValidationResult.invalid({
    required TopicValidationError error,
    required String message,
  }) {
    return TopicValidationResult._(
      isValid: false,
      error: error,
      message: message,
    );
  }

  /// Whether the topic is valid.
  final bool isValid;

  /// The sanitized topic (lowercase, trimmed) if valid.
  final String? topic;

  /// The error type if invalid.
  final TopicValidationError? error;

  /// Human-readable error message if invalid.
  final String? message;
}

/// Types of topic validation errors.
enum TopicValidationError {
  /// Topic is null.
  nullTopic,

  /// Topic is empty or whitespace only.
  emptyTopic,

  /// Topic length is not 64 characters.
  invalidLength,

  /// Topic contains non-hexadecimal characters.
  invalidCharacters,
}
