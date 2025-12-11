import 'dart:async';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/core/services/deep_link_service.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/entities/session_account.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/metamask_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/phantom_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/trust_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/rabby_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/generic_wallet_connect_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/coinbase_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/okx_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';
import 'package:wallet_integration_practice/wallet/services/wallet_adapter_factory.dart';

/// Wallet service that manages different wallet adapters.
///
/// Supports multiple accounts from a single wallet session.
/// The wallet decides which accounts to share, and this service
/// manages which account is "active" for transactions.
class WalletService {
  final WalletAdapterConfig _config;
  final Map<WalletType, BaseWalletAdapter> _adapters = {};

  BaseWalletAdapter? _activeAdapter;
  WalletEntity? _connectedWallet;

  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();
  final _accountsChangedController = StreamController<SessionAccounts>.broadcast();
  StreamSubscription? _adapterSubscription;
  StreamSubscription? _accountsSubscription;

  WalletService({WalletAdapterConfig? config})
      : _config = config ?? WalletAdapterConfig.defaultConfig() {
    _setupDeepLinkHandlers();
  }

  /// Stream of wallet connection status
  Stream<WalletConnectionStatus> get connectionStream =>
      _connectionController.stream;

  /// Get current connection status synchronously.
  ///
  /// Returns the current connection state based on adapter and wallet state.
  /// This is useful for checking status immediately without waiting for stream events.
  WalletConnectionStatus get currentConnectionStatus {
    if (_connectedWallet != null) {
      return WalletConnectionStatus.connected(_connectedWallet!);
    }

    // Check if adapter has an active session (for restoring scenarios)
    if (_activeAdapter != null && _activeAdapter!.isConnected) {
      final address = _activeAdapter!.connectedAddress;
      if (address != null) {
        // Reconstruct wallet entity from adapter state
        final wallet = WalletEntity(
          address: address,
          type: _activeAdapter!.walletType,
          chainId: _activeAdapter is EvmWalletAdapter
              ? (_activeAdapter as EvmWalletAdapter).currentChainId
              : null,
          connectedAt: DateTime.now(),
        );
        _connectedWallet = wallet;
        return WalletConnectionStatus.connected(wallet);
      }
    }

    return WalletConnectionStatus.disconnected();
  }

  /// Stream of session account changes
  Stream<SessionAccounts> get accountsChangedStream =>
      _accountsChangedController.stream;

  /// Currently connected wallet
  WalletEntity? get connectedWallet => _connectedWallet;

  /// Check if any wallet is connected
  bool get isConnected => _connectedWallet != null;

  /// Get active adapter
  BaseWalletAdapter? get activeAdapter => _activeAdapter;

  /// Check if current session has multiple accounts
  bool get hasMultipleAccounts {
    if (_activeAdapter is WalletConnectAdapter) {
      return (_activeAdapter as WalletConnectAdapter).hasMultipleAccounts;
    }
    return false;
  }

  /// Get session accounts from active adapter
  SessionAccounts get sessionAccounts {
    if (_activeAdapter is WalletConnectAdapter) {
      return (_activeAdapter as WalletConnectAdapter).sessionAccounts;
    }
    return const SessionAccounts.empty();
  }

  /// Get the active account address for transactions
  String? get activeAddress {
    if (_activeAdapter is WalletConnectAdapter) {
      return (_activeAdapter as WalletConnectAdapter).activeAddress;
    }
    return _connectedWallet?.address;
  }



// ... (existing imports)

  // ... (previous code)

  /// Initialize all adapters
  Future<void> initialize() async {
    AppLogger.wallet('Initializing wallet service');

    // Register deep link handlers for wallet callbacks
    _setupDeepLinkHandlers();

    AppLogger.wallet('Wallet service initialized');
  }

  void _setupDeepLinkHandlers() {
    final deepLinkService = DeepLinkService.instance;

    // Map of deep link keys to display names for logging
    final handlers = {
      'phantom': 'Phantom',
      'metamask': 'MetaMask',
      'wc': 'WalletConnect',
      'trust': 'Trust Wallet',
      'rabby': 'Rabby',
      'okx': 'OKX Wallet',
      'coinbase': 'Coinbase',
    };

    handlers.forEach((key, name) {
      deepLinkService.registerHandler(key, (uri) async {
        AppLogger.wallet('📱 $name deep link handler invoked', data: {'uri': uri.toString()});
        await handleDeepLink(uri);
      });
    });

    AppLogger.wallet('✅ Deep link handlers registered', data: {
      'handlers': handlers.keys.toList(),
    });
  }

  /// Get or create adapter for wallet type
  Future<BaseWalletAdapter> _getAdapter(WalletType type) async {
    if (_adapters.containsKey(type)) {
      return _adapters[type]!;
    }

    // Use Factory to create adapter
    final adapter = WalletAdapterFactory.createAdapter(type, _config);
    await adapter.initialize();
    _adapters[type] = adapter;

    return adapter;
  }
  
  // _createAdapter method removed - logic moved to WalletAdapterFactory

  /// Connect to a wallet
  Future<WalletEntity> connect({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) async {
    AppLogger.wallet('Connecting to wallet', data: {'type': walletType.name});

    _connectionController.add(WalletConnectionStatus.connecting());

    try {
      // Disconnect from current wallet if connected
      if (isConnected) {
        await disconnect();
      }

      // Get the appropriate adapter
      final adapter = await _getAdapter(walletType);
      _activeAdapter = adapter;

      // Subscribe to adapter's connection stream
      await _adapterSubscription?.cancel();
      _adapterSubscription = adapter.connectionStream.listen((status) {
        _connectionController.add(status);
        if (status.isConnected) {
          _connectedWallet = status.wallet;
        } else if (status.isDisconnected) {
          _connectedWallet = null;
        }
      });

      // Subscribe to accounts changed stream if WalletConnect adapter
      await _accountsSubscription?.cancel();
      if (adapter is WalletConnectAdapter) {
        _accountsSubscription = adapter.accountsChangedStream.listen((accounts) {
          _accountsChangedController.add(accounts);
          AppLogger.wallet('Session accounts updated', data: {
            'count': accounts.count,
            'activeAddress': accounts.activeAddress,
          });
        });
      }

      // Connect
      final wallet = await adapter.connect(
        chainId: chainId,
        cluster: cluster,
      );

      _connectedWallet = wallet;
      _connectionController.add(WalletConnectionStatus.connected(wallet));

      // Emit initial session accounts if available
      if (adapter is WalletConnectAdapter) {
        final accounts = adapter.sessionAccounts;
        if (accounts.isNotEmpty) {
          _accountsChangedController.add(accounts);
        }
      }

      AppLogger.wallet('Wallet connected', data: {
        'type': walletType.name,
        'address': wallet.address,
        'chainId': wallet.chainId,
        'hasMultipleAccounts': hasMultipleAccounts,
        'sessionAccountCount': sessionAccounts.count,
      });

      return wallet;
    } on WalletException catch (e) {
      // WalletException from adapter means all retries exhausted
      // Log with context about whether this was a retry failure
      final isRetryFailure = e.code == 'MAX_RETRIES' || e.code == 'TIMEOUT';
      AppLogger.e(
        isRetryFailure
            ? 'Wallet connection failed after retries'
            : 'Wallet connection failed',
        e,
      );

      // Don't emit error status here - adapter already emitted it via stream
      // Only rethrow to notify the caller
      rethrow;
    } catch (e) {
      // Wrap unexpected exceptions with proper context
      AppLogger.e('Unexpected wallet connection error', e);
      final wrappedException = WalletException(
        message: 'Connection failed: ${e.toString()}',
        code: 'CONNECTION_ERROR',
        originalException: e,
      );
      // Emit error for unexpected exceptions (adapter won't have emitted)
      _connectionController.add(WalletConnectionStatus.error(wrappedException.message));
      throw wrappedException;
    }
  }

  /// Disconnect from current wallet
  Future<void> disconnect() async {
    if (_activeAdapter == null) return;

    AppLogger.wallet('Disconnecting wallet');

    try {
      await _activeAdapter!.disconnect();
      _connectedWallet = null;
      _activeAdapter = null;
      await _adapterSubscription?.cancel();
      await _accountsSubscription?.cancel();
      _connectionController.add(WalletConnectionStatus.disconnected());

      AppLogger.wallet('Wallet disconnected');
    } catch (e) {
      AppLogger.e('Error disconnecting wallet', e);
      // Still clear local state
      _connectedWallet = null;
      _activeAdapter = null;
      _connectionController.add(WalletConnectionStatus.disconnected());
    }
  }

  /// Get connection URI for QR code display
  Future<String?> getConnectionUri() async {
    return _activeAdapter?.getConnectionUri();
  }

  /// Set the active account for transactions.
  ///
  /// The address must be one of the accounts approved in the session.
  /// Returns true if successful, false if the address is not in the session.
  bool setActiveAccount(String address) {
    if (_activeAdapter is WalletConnectAdapter) {
      final success = (_activeAdapter as WalletConnectAdapter).setActiveAccount(address);
      if (success) {
        // Update connected wallet with new active address
        if (_connectedWallet != null) {
          _connectedWallet = _connectedWallet!.copyWith(address: address);
          _connectionController.add(WalletConnectionStatus.connected(_connectedWallet!));
        }
      }
      return success;
    }
    return false;
  }

  /// Get all unique addresses from the session
  List<String> getSessionAddresses() {
    return sessionAccounts.uniqueAddresses;
  }

  /// Get all session accounts with full details
  List<SessionAccount> getSessionAccountsList() {
    return sessionAccounts.accounts;
  }

  /// Switch to a different chain
  Future<void> switchChain(int chainId) async {
    if (_activeAdapter == null) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    await _activeAdapter!.switchChain(chainId);
  }

  /// Send transaction
  Future<TransactionResult> sendTransaction(TransactionRequest request) async {
    if (_activeAdapter == null) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final hash = await _activeAdapter!.sendTransaction(request);

      return TransactionResult(
        hash: hash,
        status: TransactionStatus.pending,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      AppLogger.e('Transaction failed', e);
      rethrow;
    }
  }

  /// Sign personal message
  Future<SignatureResult> personalSign(PersonalSignRequest request) async {
    if (_activeAdapter == null) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final signature = await _activeAdapter!.personalSign(
        request.message,
        request.address,
      );

      return SignatureResult(
        signature: signature,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      AppLogger.e('Signing failed', e);
      rethrow;
    }
  }

  /// Sign typed data (EIP-712)
  Future<SignatureResult> signTypedData(TypedDataSignRequest request) async {
    if (_activeAdapter == null) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final signature = await _activeAdapter!.signTypedData(
        request.address,
        request.typedData,
      );

      return SignatureResult(
        signature: signature,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      AppLogger.e('Typed data signing failed', e);
      rethrow;
    }
  }

  /// Handle deep link callback from wallet apps
  Future<void> handleDeepLink(Uri uri) async {
    AppLogger.wallet('🔗 Handling deep link in WalletService', data: {
      'uri': uri.toString(),
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
    });

    final host = uri.host;
    final path = uri.path;

    // Route to appropriate adapter
    if (host == 'phantom' || path.contains('phantom')) {
      final phantomAdapter = _adapters[WalletType.phantom];
      AppLogger.wallet('🔍 Looking for Phantom adapter', data: {
        'found': phantomAdapter != null,
        'isPhantomAdapter': phantomAdapter is PhantomAdapter,
        'availableAdapters': _adapters.keys.map((k) => k.name).toList(),
      });

      if (phantomAdapter is PhantomAdapter) {
        AppLogger.wallet('✅ Routing to Phantom adapter');
        await phantomAdapter.handleDeepLinkCallback(uri);
      } else {
        AppLogger.e('❌ Phantom adapter not found! Deep link will be ignored.');
      }
    } else if (host == 'trust' || path.contains('trust')) {
      // Trust Wallet uses WalletConnect, callback handled by WC session
      AppLogger.wallet('Trust Wallet deep link received', data: {'uri': uri.toString()});
    } else {
      AppLogger.wallet('⚠️ Unhandled deep link', data: {'host': host, 'path': path});
    }
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await _adapterSubscription?.cancel();
    await _accountsSubscription?.cancel();

    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }

    _adapters.clear();
    await _connectionController.close();
    await _accountsChangedController.close();
  }
}
