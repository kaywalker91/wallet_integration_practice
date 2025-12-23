import 'package:equatable/equatable.dart';
import 'package:wallet_integration_practice/domain/entities/connected_wallet_entry.dart';

/// State management for multiple connected wallets.
///
/// This class manages a collection of [ConnectedWalletEntry] objects
/// and tracks which wallet is currently active for operations.
class MultiWalletState extends Equatable {
  const MultiWalletState({
    this.wallets = const [],
    this.activeWalletId,
    this.isLoading = false,
    this.globalError,
  });

  /// List of all wallet entries (connected, disconnected, or errored)
  final List<ConnectedWalletEntry> wallets;

  /// ID of the currently active wallet for operations
  final String? activeWalletId;

  /// Whether a global operation is in progress
  final bool isLoading;

  /// Global error message for operations affecting all wallets
  final String? globalError;

  /// Get the currently active wallet entry
  ConnectedWalletEntry? get activeWallet {
    if (activeWalletId == null) return null;
    try {
      return wallets.firstWhere((w) => w.id == activeWalletId);
    } catch (_) {
      return null;
    }
  }

  /// Get all connected wallets (status == connected)
  List<ConnectedWalletEntry> get connectedWallets {
    return wallets
        .where((w) => w.status == WalletEntryStatus.connected)
        .toList();
  }

  /// Get all wallets sorted by last activity (most recent first)
  List<ConnectedWalletEntry> get walletsByActivity {
    final sorted = List<ConnectedWalletEntry>.from(wallets);
    sorted.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    return sorted;
  }

  /// Number of connected wallets
  int get connectedCount => connectedWallets.length;

  /// Total number of wallet entries
  int get totalCount => wallets.length;

  /// Whether there is an active wallet
  bool get hasActiveWallet => activeWallet != null;

  /// Whether any wallet is currently connecting
  bool get hasConnectingWallet {
    return wallets.any((w) => w.status == WalletEntryStatus.connecting);
  }

  /// Whether any wallet has an error
  bool get hasErrorWallet {
    return wallets.any((w) => w.status == WalletEntryStatus.error);
  }

  /// Check if a wallet with the given ID exists
  bool containsWallet(String id) {
    return wallets.any((w) => w.id == id);
  }

  /// Get a wallet by ID
  ConnectedWalletEntry? getWallet(String id) {
    try {
      return wallets.firstWhere((w) => w.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Create a copy with updated values
  MultiWalletState copyWith({
    List<ConnectedWalletEntry>? wallets,
    String? activeWalletId,
    bool clearActiveWalletId = false,
    bool? isLoading,
    String? globalError,
    bool clearGlobalError = false,
  }) {
    return MultiWalletState(
      wallets: wallets ?? this.wallets,
      activeWalletId:
          clearActiveWalletId ? null : (activeWalletId ?? this.activeWalletId),
      isLoading: isLoading ?? this.isLoading,
      globalError:
          clearGlobalError ? null : (globalError ?? this.globalError),
    );
  }

  /// Add a new wallet entry
  MultiWalletState addWallet(ConnectedWalletEntry entry) {
    // Check if wallet with same ID already exists
    if (containsWallet(entry.id)) {
      return updateWallet(entry.id, (_) => entry);
    }
    return copyWith(wallets: [...wallets, entry]);
  }

  /// Remove a wallet entry by ID
  MultiWalletState removeWallet(String id) {
    final newWallets = wallets.where((w) => w.id != id).toList();
    final newActiveId = activeWalletId == id ? null : activeWalletId;

    // If we removed the active wallet, select the next connected one
    String? nextActiveId = newActiveId;
    if (newActiveId == null && newWallets.isNotEmpty) {
      final connected = newWallets
          .where((w) => w.status == WalletEntryStatus.connected)
          .toList();
      if (connected.isNotEmpty) {
        // Select the most recently active one
        connected.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
        nextActiveId = connected.first.id;
      }
    }

    return copyWith(
      wallets: newWallets,
      activeWalletId: nextActiveId,
      clearActiveWalletId: nextActiveId == null,
    );
  }

  /// Update a wallet entry by ID
  MultiWalletState updateWallet(
    String id,
    ConnectedWalletEntry Function(ConnectedWalletEntry) update,
  ) {
    final newWallets = wallets.map((w) {
      if (w.id == id) {
        return update(w);
      }
      return w;
    }).toList();
    return copyWith(wallets: newWallets);
  }

  /// Set the active wallet by ID
  MultiWalletState setActiveWallet(String id) {
    if (!containsWallet(id)) return this;

    // Update isActive flags on all wallets
    final newWallets = wallets.map((w) {
      if (w.id == id) {
        return w.setActive(true);
      } else if (w.isActive) {
        return w.setActive(false);
      }
      return w;
    }).toList();

    return copyWith(
      wallets: newWallets,
      activeWalletId: id,
    );
  }

  /// Clear active wallet selection
  MultiWalletState clearActiveWallet() {
    final newWallets = wallets.map((w) {
      if (w.isActive) {
        return w.setActive(false);
      }
      return w;
    }).toList();

    return copyWith(
      wallets: newWallets,
      clearActiveWalletId: true,
    );
  }

  @override
  List<Object?> get props => [
        wallets,
        activeWalletId,
        isLoading,
        globalError,
      ];
}
