import 'package:equatable/equatable.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';

/// Status of a wallet entry in the multi-wallet list
enum WalletEntryStatus {
  /// Currently attempting to connect
  connecting,

  /// Successfully connected and ready for use
  connected,

  /// Disconnected but still in the list
  disconnected,

  /// Connection failed with error
  error,
}

/// Extension to provide display properties for wallet entry status
extension WalletEntryStatusX on WalletEntryStatus {
  String get displayName {
    switch (this) {
      case WalletEntryStatus.connecting:
        return 'Connecting';
      case WalletEntryStatus.connected:
        return 'Connected';
      case WalletEntryStatus.disconnected:
        return 'Disconnected';
      case WalletEntryStatus.error:
        return 'Error';
    }
  }

  bool get isConnected => this == WalletEntryStatus.connected;
  bool get isConnecting => this == WalletEntryStatus.connecting;
  bool get isDisconnected => this == WalletEntryStatus.disconnected;
  bool get hasError => this == WalletEntryStatus.error;
}

/// Represents a single wallet entry in the multi-wallet connection list.
///
/// Each entry wraps a [WalletEntity] with additional status tracking
/// for the multi-wallet UI.
class ConnectedWalletEntry extends Equatable {
  /// Unique identifier for this entry (type_address)
  final String id;

  /// The underlying wallet entity
  final WalletEntity wallet;

  /// Current connection status
  final WalletEntryStatus status;

  /// Error message if status is [WalletEntryStatus.error]
  final String? errorMessage;

  /// Whether this is the currently active wallet for operations
  final bool isActive;

  /// Timestamp of last activity (connection, selection, etc.)
  final DateTime lastActivityAt;

  const ConnectedWalletEntry({
    required this.id,
    required this.wallet,
    required this.status,
    this.errorMessage,
    this.isActive = false,
    required this.lastActivityAt,
  });

  /// Generate a unique ID from wallet properties.
  /// Format: {walletType}_{lowercaseAddress}
  static String generateId(WalletEntity wallet) {
    return '${wallet.type.name}_${wallet.address.toLowerCase()}';
  }

  /// Create a new entry from a wallet entity with connecting status
  factory ConnectedWalletEntry.connecting(WalletEntity wallet) {
    return ConnectedWalletEntry(
      id: generateId(wallet),
      wallet: wallet,
      status: WalletEntryStatus.connecting,
      lastActivityAt: DateTime.now(),
    );
  }

  /// Create a new entry from a wallet entity with connected status
  factory ConnectedWalletEntry.connected(
    WalletEntity wallet, {
    bool isActive = false,
  }) {
    return ConnectedWalletEntry(
      id: generateId(wallet),
      wallet: wallet,
      status: WalletEntryStatus.connected,
      isActive: isActive,
      lastActivityAt: DateTime.now(),
    );
  }

  /// Create a new entry with error status
  factory ConnectedWalletEntry.error(
    WalletEntity wallet,
    String errorMessage,
  ) {
    return ConnectedWalletEntry(
      id: generateId(wallet),
      wallet: wallet,
      status: WalletEntryStatus.error,
      errorMessage: errorMessage,
      lastActivityAt: DateTime.now(),
    );
  }

  /// Create a copy with updated values
  ConnectedWalletEntry copyWith({
    String? id,
    WalletEntity? wallet,
    WalletEntryStatus? status,
    String? errorMessage,
    bool? isActive,
    DateTime? lastActivityAt,
  }) {
    return ConnectedWalletEntry(
      id: id ?? this.id,
      wallet: wallet ?? this.wallet,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isActive: isActive ?? this.isActive,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    );
  }

  /// Clear error and set to disconnected status
  ConnectedWalletEntry clearError() {
    return copyWith(
      status: WalletEntryStatus.disconnected,
      errorMessage: null,
    );
  }

  /// Set as active wallet
  ConnectedWalletEntry setActive(bool active) {
    return copyWith(
      isActive: active,
      lastActivityAt: active ? DateTime.now() : lastActivityAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        wallet,
        status,
        errorMessage,
        isActive,
        lastActivityAt,
      ];
}
