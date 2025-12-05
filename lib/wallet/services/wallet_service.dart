import 'dart:async';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/walletconnect_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/metamask_adapter.dart';
import 'package:wallet_integration_practice/wallet/adapters/phantom_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';

/// Wallet service that manages different wallet adapters
class WalletService {
  final WalletAdapterConfig _config;
  final Map<WalletType, BaseWalletAdapter> _adapters = {};

  BaseWalletAdapter? _activeAdapter;
  WalletEntity? _connectedWallet;

  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();
  StreamSubscription? _adapterSubscription;

  WalletService({WalletAdapterConfig? config})
      : _config = config ?? WalletAdapterConfig.defaultConfig();

  /// Stream of wallet connection status
  Stream<WalletConnectionStatus> get connectionStream =>
      _connectionController.stream;

  /// Currently connected wallet
  WalletEntity? get connectedWallet => _connectedWallet;

  /// Check if any wallet is connected
  bool get isConnected => _connectedWallet != null;

  /// Get active adapter
  BaseWalletAdapter? get activeAdapter => _activeAdapter;

  /// Initialize all adapters
  Future<void> initialize() async {
    AppLogger.wallet('Initializing wallet service');

    // Initialize adapters lazily on first use
    // This prevents unnecessary initialization of unused adapters

    AppLogger.wallet('Wallet service initialized');
  }

  /// Get or create adapter for wallet type
  Future<BaseWalletAdapter> _getAdapter(WalletType type) async {
    if (_adapters.containsKey(type)) {
      return _adapters[type]!;
    }

    final adapter = _createAdapter(type);
    await adapter.initialize();
    _adapters[type] = adapter;

    return adapter;
  }

  BaseWalletAdapter _createAdapter(WalletType type) {
    switch (type) {
      case WalletType.metamask:
        return MetaMaskAdapter(config: _config);
      case WalletType.walletConnect:
        return WalletConnectAdapter(config: _config);
      case WalletType.phantom:
        return PhantomAdapter();
      case WalletType.coinbase:
      case WalletType.trustWallet:
      case WalletType.rainbow:
      case WalletType.rabby:
        // These wallets use WalletConnect
        return WalletConnectAdapter(config: _config);
    }
  }

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

      // Connect
      final wallet = await adapter.connect(
        chainId: chainId,
        cluster: cluster,
      );

      _connectedWallet = wallet;
      _connectionController.add(WalletConnectionStatus.connected(wallet));

      AppLogger.wallet('Wallet connected', data: {
        'type': walletType.name,
        'address': wallet.address,
        'chainId': wallet.chainId,
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
    AppLogger.wallet('Handling deep link in WalletService', data: {'uri': uri.toString()});

    final host = uri.host;
    final path = uri.path;

    // Route to appropriate adapter
    if (host == 'phantom' || path.contains('phantom')) {
      final phantomAdapter = _adapters[WalletType.phantom];
      if (phantomAdapter is PhantomAdapter) {
        await phantomAdapter.handleDeepLinkCallback(uri);
      }
    }
    // Add more wallet-specific deep link handling as needed
  }

  /// Dispose all resources
  Future<void> dispose() async {
    await _adapterSubscription?.cancel();

    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }

    _adapters.clear();
    await _connectionController.close();
  }
}
