/// String extensions for common operations
extension StringExtensions on String {
  /// Truncate string with ellipsis
  String truncateWithEllipsis(int maxLength) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}...';
  }

  /// Check if string is a valid hex string
  bool get isValidHex {
    if (startsWith('0x')) {
      return RegExp(r'^0x[0-9a-fA-F]+$').hasMatch(this);
    }
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(this);
  }

  /// Add 0x prefix if not present
  String get withHexPrefix {
    if (startsWith('0x')) return this;
    return '0x$this';
  }

  /// Remove 0x prefix if present
  String get withoutHexPrefix {
    if (startsWith('0x')) return substring(2);
    return this;
  }

  /// Capitalize first letter
  String get capitalized {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

/// Nullable string extensions
extension NullableStringExtensions on String? {
  /// Returns true if string is null or empty
  bool get isNullOrEmpty => this == null || this!.isEmpty;

  /// Returns true if string is not null and not empty
  bool get isNotNullOrEmpty => this != null && this!.isNotEmpty;
}
