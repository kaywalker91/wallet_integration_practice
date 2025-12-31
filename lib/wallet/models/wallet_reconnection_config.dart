/// Configuration for wallet reconnection behavior.
///
/// Different wallets have different characteristics when it comes to
/// relay connectivity and session restoration. This config allows
/// customization of reconnection parameters per wallet type.
class WalletReconnectionConfig {
  const WalletReconnectionConfig({
    required this.reconnectTimeouts,
    required this.reconnectDelay,
    required this.prePollDelay,
    required this.maxSessionPolls,
    required this.sessionPollInterval,
    required this.relayPropagationDelay,
  });

  /// Standard configuration for most wallets.
  ///
  /// Uses moderate timeouts suitable for wallets with good
  /// relay connectivity.
  factory WalletReconnectionConfig.standard() {
    return const WalletReconnectionConfig(
      reconnectTimeouts: [5, 7, 10],
      reconnectDelay: Duration(milliseconds: 500),
      prePollDelay: Duration(milliseconds: 500),
      maxSessionPolls: 3,
      sessionPollInterval: Duration(seconds: 1),
      relayPropagationDelay: Duration(milliseconds: 200),
    );
  }

  /// Aggressive configuration for wallets with known relay issues.
  ///
  /// OKX Wallet requires more aggressive reconnection due to
  /// Android background network restrictions and slower relay propagation.
  factory WalletReconnectionConfig.aggressive() {
    return const WalletReconnectionConfig(
      reconnectTimeouts: [3, 4, 5], // Faster initial attempts
      reconnectDelay: Duration(milliseconds: 300),
      prePollDelay: Duration(milliseconds: 1000), // Longer pre-poll for relay stabilization
      maxSessionPolls: 5,
      sessionPollInterval: Duration(seconds: 1),
      relayPropagationDelay: Duration(milliseconds: 300),
    );
  }

  /// Medium configuration for wallets with moderate relay needs.
  ///
  /// Suitable for Trust Wallet, Coinbase, and similar wallets
  /// that have occasional relay issues but are generally stable.
  factory WalletReconnectionConfig.medium() {
    return const WalletReconnectionConfig(
      reconnectTimeouts: [4, 6, 8],
      reconnectDelay: Duration(milliseconds: 400),
      prePollDelay: Duration(milliseconds: 700),
      maxSessionPolls: 4,
      sessionPollInterval: Duration(seconds: 1),
      relayPropagationDelay: Duration(milliseconds: 250),
    );
  }

  /// Lenient configuration for well-behaved wallets.
  ///
  /// MetaMask and Rabby have good relay connectivity and
  /// don't need aggressive reconnection strategies.
  factory WalletReconnectionConfig.lenient() {
    return const WalletReconnectionConfig(
      reconnectTimeouts: [5, 10, 15],
      reconnectDelay: Duration(milliseconds: 500),
      prePollDelay: Duration(milliseconds: 300),
      maxSessionPolls: 3,
      sessionPollInterval: Duration(seconds: 2),
      relayPropagationDelay: Duration(milliseconds: 150),
    );
  }

  /// Progressive reconnect timeouts in seconds.
  ///
  /// Each attempt uses the next timeout in the list.
  /// Example: [3, 4, 5] means 3s, 4s, then 5s.
  final List<int> reconnectTimeouts;

  /// Delay between reconnection attempts.
  final Duration reconnectDelay;

  /// Delay before starting session polling.
  ///
  /// Allows relay connection to stabilize before checking for sessions.
  final Duration prePollDelay;

  /// Maximum number of session poll attempts.
  final int maxSessionPolls;

  /// Interval between session poll attempts.
  final Duration sessionPollInterval;

  /// Delay to allow relay message propagation.
  ///
  /// Some wallets need extra time for session proposals
  /// to propagate through the relay network.
  final Duration relayPropagationDelay;

  /// Total reconnection budget (sum of all timeouts).
  int get totalTimeoutSeconds => reconnectTimeouts.fold(0, (a, b) => a + b);

  /// Total reconnection budget as Duration.
  Duration get totalTimeout => Duration(seconds: totalTimeoutSeconds);

  @override
  String toString() {
    return 'WalletReconnectionConfig('
        'timeouts: $reconnectTimeouts, '
        'delay: ${reconnectDelay.inMilliseconds}ms, '
        'prePoll: ${prePollDelay.inMilliseconds}ms, '
        'polls: $maxSessionPolls)';
  }

  /// Create a copy with modified values.
  WalletReconnectionConfig copyWith({
    List<int>? reconnectTimeouts,
    Duration? reconnectDelay,
    Duration? prePollDelay,
    int? maxSessionPolls,
    Duration? sessionPollInterval,
    Duration? relayPropagationDelay,
  }) {
    return WalletReconnectionConfig(
      reconnectTimeouts: reconnectTimeouts ?? this.reconnectTimeouts,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      prePollDelay: prePollDelay ?? this.prePollDelay,
      maxSessionPolls: maxSessionPolls ?? this.maxSessionPolls,
      sessionPollInterval: sessionPollInterval ?? this.sessionPollInterval,
      relayPropagationDelay: relayPropagationDelay ?? this.relayPropagationDelay,
    );
  }
}
