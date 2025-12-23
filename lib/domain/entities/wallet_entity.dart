import 'package:equatable/equatable.dart';
import 'package:wallet_integration_practice/core/constants/wallet_constants.dart';

/// Connected wallet entity
class WalletEntity extends Equatable {
  const WalletEntity({
    required this.address,
    required this.type,
    this.chainId,
    this.cluster,
    this.sessionTopic,
    required this.connectedAt,
    this.metadata,
  });

  final String address;
  final WalletType type;
  final int? chainId;
  final String? cluster; // For Solana
  final String? sessionTopic;
  final DateTime connectedAt;
  final Map<String, dynamic>? metadata;

  /// Check if connected to EVM chain
  bool get isEvmChain => chainId != null;

  /// Check if connected to Solana
  bool get isSolanaChain => cluster != null;

  /// Get display name of wallet type
  String get walletName => type.displayName;

  /// Create a copy with updated values
  WalletEntity copyWith({
    String? address,
    WalletType? type,
    int? chainId,
    String? cluster,
    String? sessionTopic,
    DateTime? connectedAt,
    Map<String, dynamic>? metadata,
  }) {
    return WalletEntity(
      address: address ?? this.address,
      type: type ?? this.type,
      chainId: chainId ?? this.chainId,
      cluster: cluster ?? this.cluster,
      sessionTopic: sessionTopic ?? this.sessionTopic,
      connectedAt: connectedAt ?? this.connectedAt,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [
        address,
        type,
        chainId,
        cluster,
        sessionTopic,
        connectedAt,
      ];
}

/// Wallet connection state
enum WalletConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Wallet connection status
class WalletConnectionStatus extends Equatable {
  const WalletConnectionStatus({
    required this.state,
    this.wallet,
    this.errorMessage,
    this.progressMessage,
    this.retryCount,
    this.maxRetries,
  });

  factory WalletConnectionStatus.disconnected() {
    return const WalletConnectionStatus(
      state: WalletConnectionState.disconnected,
    );
  }

  factory WalletConnectionStatus.connecting({
    String? message,
    int? retryCount,
    int? maxRetries,
  }) {
    return WalletConnectionStatus(
      state: WalletConnectionState.connecting,
      progressMessage: message ?? 'Connecting to wallet...',
      retryCount: retryCount,
      maxRetries: maxRetries,
    );
  }

  factory WalletConnectionStatus.connected(WalletEntity wallet) {
    return WalletConnectionStatus(
      state: WalletConnectionState.connected,
      wallet: wallet,
    );
  }

  factory WalletConnectionStatus.error(String message) {
    return WalletConnectionStatus(
      state: WalletConnectionState.error,
      errorMessage: message,
    );
  }

  final WalletConnectionState state;
  final WalletEntity? wallet;
  final String? errorMessage;
  final String? progressMessage;
  final int? retryCount;
  final int? maxRetries;

  bool get isConnected => state == WalletConnectionState.connected;
  bool get isConnecting => state == WalletConnectionState.connecting;
  bool get isDisconnected => state == WalletConnectionState.disconnected;
  bool get hasError => state == WalletConnectionState.error;
  bool get isRetrying => isConnecting && retryCount != null && retryCount! > 0;

  @override
  List<Object?> get props => [state, wallet, errorMessage, progressMessage, retryCount, maxRetries];
}
