import 'package:equatable/equatable.dart';

/// Represents a single account from a WalletConnect session.
///
/// Follows CAIP-10 format: namespace:chainId:address
/// Example: "eip155:1:0xab16a96d359ec26a11e2c2b3d8f8b8942d5bfcdb"
class SessionAccount extends Equatable {
  /// Full CAIP-10 account identifier
  final String caip10Id;

  /// Namespace (e.g., "eip155" for EVM, "solana" for Solana)
  final String namespace;

  /// Chain ID as string (e.g., "1" for Ethereum mainnet, "137" for Polygon)
  final String chainId;

  /// Wallet address
  final String address;

  /// Optional display name for the account
  final String? displayName;

  const SessionAccount({
    required this.caip10Id,
    required this.namespace,
    required this.chainId,
    required this.address,
    this.displayName,
  });

  /// Parse a CAIP-10 formatted account string.
  ///
  /// Format: "namespace:chainId:address"
  /// Example: "eip155:1:0xab16a96d359ec26a11e2c2b3d8f8b8942d5bfcdb"
  factory SessionAccount.fromCaip10(String caip10Account) {
    final parts = caip10Account.split(':');
    if (parts.length < 3) {
      throw FormatException(
        'Invalid CAIP-10 format. Expected "namespace:chainId:address", got "$caip10Account"',
      );
    }

    return SessionAccount(
      caip10Id: caip10Account,
      namespace: parts[0],
      chainId: parts[1],
      // Address might contain colons (unlikely but handle it)
      address: parts.sublist(2).join(':'),
    );
  }

  /// Create from individual components
  factory SessionAccount.create({
    required String namespace,
    required String chainId,
    required String address,
    String? displayName,
  }) {
    return SessionAccount(
      caip10Id: '$namespace:$chainId:$address',
      namespace: namespace,
      chainId: chainId,
      address: address,
      displayName: displayName,
    );
  }

  /// Check if this is an EVM account
  bool get isEvm => namespace == 'eip155';

  /// Check if this is a Solana account
  bool get isSolana => namespace == 'solana';

  /// Get chain ID as integer (for EVM chains)
  int? get chainIdInt => int.tryParse(chainId);

  /// Get shortened address for display (e.g., "0xab16...fcdb")
  String get shortAddress {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// Get display label (name or short address)
  String get displayLabel => displayName ?? shortAddress;

  /// Create a copy with updated values
  SessionAccount copyWith({
    String? caip10Id,
    String? namespace,
    String? chainId,
    String? address,
    String? displayName,
  }) {
    return SessionAccount(
      caip10Id: caip10Id ?? this.caip10Id,
      namespace: namespace ?? this.namespace,
      chainId: chainId ?? this.chainId,
      address: address ?? this.address,
      displayName: displayName ?? this.displayName,
    );
  }

  @override
  List<Object?> get props => [caip10Id, namespace, chainId, address, displayName];

  @override
  String toString() => 'SessionAccount($caip10Id)';
}

/// Collection of session accounts with active account tracking.
///
/// Manages multiple accounts from a single WalletConnect session,
/// allowing the user to select which account to use for transactions.
class SessionAccounts extends Equatable {
  /// All accounts approved in the session
  final List<SessionAccount> accounts;

  /// Currently active account address for transactions
  final String? activeAddress;

  const SessionAccounts({
    required this.accounts,
    this.activeAddress,
  });

  /// Create empty session accounts
  const SessionAccounts.empty()
      : accounts = const [],
        activeAddress = null;

  /// Parse accounts from session namespaces.
  ///
  /// Takes the accounts array from session.namespaces['eip155'].accounts
  /// which contains CAIP-10 formatted strings.
  factory SessionAccounts.fromNamespaceAccounts(List<String> caip10Accounts) {
    if (caip10Accounts.isEmpty) {
      return const SessionAccounts.empty();
    }

    final accounts = caip10Accounts
        .map((acc) => SessionAccount.fromCaip10(acc))
        .toList();

    // First account is the default active one
    return SessionAccounts(
      accounts: accounts,
      activeAddress: accounts.first.address,
    );
  }

  /// Get the currently active account
  SessionAccount? get activeAccount {
    if (activeAddress == null) return null;
    try {
      return accounts.firstWhere(
        (acc) => acc.address.toLowerCase() == activeAddress!.toLowerCase(),
      );
    } catch (_) {
      return accounts.isNotEmpty ? accounts.first : null;
    }
  }

  /// Get unique addresses (deduplicated across chains)
  List<String> get uniqueAddresses {
    return accounts.map((a) => a.address.toLowerCase()).toSet().toList();
  }

  /// Get accounts for a specific chain
  List<SessionAccount> accountsForChain(String chainId) {
    return accounts.where((acc) => acc.chainId == chainId).toList();
  }

  /// Get accounts for a specific chain ID (integer)
  List<SessionAccount> accountsForChainId(int chainId) {
    return accountsForChain(chainId.toString());
  }

  /// Get all unique chain IDs
  List<String> get chainIds {
    return accounts.map((a) => a.chainId).toSet().toList();
  }

  /// Check if multiple unique addresses exist
  bool get hasMultipleAddresses => uniqueAddresses.length > 1;

  /// Number of accounts
  int get count => accounts.length;

  /// Check if empty
  bool get isEmpty => accounts.isEmpty;

  /// Check if not empty
  bool get isNotEmpty => accounts.isNotEmpty;

  /// Check if an address is in the session
  bool containsAddress(String address) {
    return accounts.any(
      (acc) => acc.address.toLowerCase() == address.toLowerCase(),
    );
  }

  /// Set the active account by address
  SessionAccounts setActiveAddress(String address) {
    if (!containsAddress(address)) return this;
    return SessionAccounts(
      accounts: accounts,
      activeAddress: address,
    );
  }

  /// Update accounts (e.g., from accountsChanged event)
  SessionAccounts updateAccounts(List<String> caip10Accounts) {
    final newAccounts = caip10Accounts
        .map((acc) => SessionAccount.fromCaip10(acc))
        .toList();

    // Keep current active if still valid, otherwise use first
    String? newActive = activeAddress;
    if (newActive != null && !newAccounts.any(
      (acc) => acc.address.toLowerCase() == newActive!.toLowerCase(),
    )) {
      newActive = newAccounts.isNotEmpty ? newAccounts.first.address : null;
    }

    return SessionAccounts(
      accounts: newAccounts,
      activeAddress: newActive,
    );
  }

  /// Create a copy with updated values
  SessionAccounts copyWith({
    List<SessionAccount>? accounts,
    String? activeAddress,
    bool clearActiveAddress = false,
  }) {
    return SessionAccounts(
      accounts: accounts ?? this.accounts,
      activeAddress: clearActiveAddress ? null : (activeAddress ?? this.activeAddress),
    );
  }

  @override
  List<Object?> get props => [accounts, activeAddress];
}
