import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';

/// Phantom wallet adapter for Solana
class PhantomAdapter extends SolanaWalletAdapter {
  bool _isInitialized = false;
  String? _connectedAddress;
  String? _session;
  String? _currentCluster;

  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();

  // Phantom deep link response handling
  StreamSubscription? _linkSubscription;

  @override
  WalletType get walletType => WalletType.phantom;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isConnected => _connectedAddress != null;

  @override
  String? get connectedAddress => _connectedAddress;

  @override
  int? get currentChainId => null; // Solana doesn't use chain IDs

  @override
  String? get currentCluster => _currentCluster;

  @override
  Stream<WalletConnectionStatus> get connectionStream =>
      _connectionController.stream;

  /// Check if Phantom is installed
  Future<bool> isPhantomInstalled() async {
    try {
      final uri = Uri.parse(WalletConstants.phantomDeepLink);
      return await canLaunchUrl(uri);
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    AppLogger.wallet('Initializing Phantom adapter');

    // Setup deep link listener for Phantom responses
    // This would need app_links or uni_links package integration
    // For now, we'll handle it through the connect flow

    _isInitialized = true;
    AppLogger.wallet('Phantom adapter initialized');
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    if (!_isInitialized) {
      await initialize();
    }

    _connectionController.add(WalletConnectionStatus.connecting());
    _currentCluster = cluster ?? ChainConstants.solanaMainnet;

    try {
      // Build Phantom connect deep link
      final connectUrl = _buildConnectUrl();

      // Try to launch Phantom directly
      // (canLaunchUrl is unreliable on Android 11+)
      final launched = await launchUrl(
        Uri.parse(connectUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        // launchUrl returned false = app not installed
        throw WalletNotInstalledException(
          walletType: walletType.name,
          message: 'Phantom wallet is not installed',
        );
      }

      // In a real implementation, we'd wait for the deep link callback
      // For now, we'll simulate the connection process
      // The actual implementation would use app_links to listen for the callback

      AppLogger.wallet('Phantom connect requested', data: {'cluster': _currentCluster});

      // Wait for user to approve in Phantom app
      // This would be handled by deep link callback in production
      await Future.delayed(const Duration(seconds: 2));

      // Placeholder - in production, this would come from the deep link callback
      throw const WalletException(
        message: 'Phantom connection requires deep link callback implementation',
        code: 'NOT_IMPLEMENTED',
      );
    } catch (e) {
      AppLogger.e('Phantom connection failed', e);
      _connectionController.add(WalletConnectionStatus.error(e.toString()));
      rethrow;
    }
  }

  /// Handle deep link callback from Phantom
  Future<void> handleDeepLinkCallback(Uri uri) async {
    AppLogger.wallet('Handling Phantom callback', data: {'uri': uri.toString()});

    try {
      // Parse the callback parameters
      final params = uri.queryParameters;

      if (params.containsKey('errorCode')) {
        final errorMessage = params['errorMessage'] ?? 'Unknown error';
        _connectionController.add(WalletConnectionStatus.error(errorMessage));
        return;
      }

      // Extract the public key (wallet address)
      final publicKey = params['phantom_encryption_public_key'];
      final data = params['data'];
      final nonce = params['nonce'];

      if (data != null && nonce != null) {
        // Decrypt the response to get the actual public key
        // This requires implementing Phantom's encryption scheme
        // For now, we'll use a placeholder

        _connectedAddress = publicKey; // Simplified - actual implementation needs decryption
        _session = params['session'];

        if (_connectedAddress != null) {
          final wallet = WalletEntity(
            address: _connectedAddress!,
            type: walletType,
            cluster: _currentCluster,
            sessionTopic: _session,
            connectedAt: DateTime.now(),
          );

          _connectionController.add(WalletConnectionStatus.connected(wallet));
          AppLogger.wallet('Phantom connected', data: {'address': _connectedAddress});
        }
      }
    } catch (e) {
      AppLogger.e('Error handling Phantom callback', e);
      _connectionController.add(WalletConnectionStatus.error(e.toString()));
    }
  }

  String _buildConnectUrl() {
    final appUrl = Uri.encodeComponent(
      '${AppConstants.deepLinkScheme}://phantom/callback',
    );
    final cluster = Uri.encodeComponent(_currentCluster ?? 'mainnet-beta');
    final redirectLink = Uri.encodeComponent(appUrl);

    return '${WalletConstants.phantomConnectUrl}/connect'
        '?app_url=${Uri.encodeComponent(AppConstants.appUrl)}'
        '&dapp_encryption_public_key=YOUR_DAPP_PUBLIC_KEY' // Would be generated
        '&redirect_link=$redirectLink'
        '&cluster=$cluster';
  }

  Future<void> _openAppStore() async {
    try {
      String storeUrl;
      if (Platform.isIOS) {
        storeUrl =
            'https://apps.apple.com/app/id${WalletConstants.phantomAppStoreId}';
      } else if (Platform.isAndroid) {
        storeUrl =
            'https://play.google.com/store/apps/details?id=${WalletConstants.phantomPackageAndroid}';
      } else {
        return;
      }

      final uri = Uri.parse(storeUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening app store', e);
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) return;

    try {
      // Build disconnect URL
      final disconnectUrl = '${WalletConstants.phantomConnectUrl}/disconnect'
          '?session=${Uri.encodeComponent(_session ?? '')}';

      await launchUrl(
        Uri.parse(disconnectUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      AppLogger.e('Error disconnecting from Phantom', e);
    } finally {
      _connectedAddress = null;
      _session = null;
      _connectionController.add(WalletConnectionStatus.disconnected());
    }
  }

  @override
  Future<String?> getConnectionUri() async {
    // Phantom uses deep links, not WalletConnect URIs
    return null;
  }

  @override
  Future<void> switchChain(int chainId) async {
    // Solana doesn't have chain IDs - clusters are switched differently
    throw const WalletException(
      message: 'Use switchCluster for Solana',
      code: 'UNSUPPORTED',
    );
  }

  /// Switch Solana cluster
  Future<void> switchCluster(String cluster) async {
    _currentCluster = cluster;
    // Would need to reconnect with new cluster
  }

  @override
  Future<String> sendTransaction(TransactionRequest request) async {
    throw const WalletException(
      message: 'Use signAndSendTransaction for Solana',
      code: 'UNSUPPORTED',
    );
  }

  @override
  Future<String> personalSign(String message, String address) async {
    if (!isConnected) {
      throw const WalletException(
        message: 'Not connected to Phantom',
        code: 'NOT_CONNECTED',
      );
    }

    // Build sign message URL
    final encodedMessage = base64Encode(utf8.encode(message));
    final signUrl = '${WalletConstants.phantomConnectUrl}/signMessage'
        '?session=${Uri.encodeComponent(_session ?? '')}'
        '&message=$encodedMessage';

    await launchUrl(
      Uri.parse(signUrl),
      mode: LaunchMode.externalApplication,
    );

    // In production, would wait for callback with signature
    throw const WalletException(
      message: 'Signature handling requires deep link callback',
      code: 'NOT_IMPLEMENTED',
    );
  }

  @override
  Future<String> signTypedData(
    String address,
    Map<String, dynamic> typedData,
  ) async {
    throw const WalletException(
      message: 'Typed data signing not supported on Solana',
      code: 'UNSUPPORTED',
    );
  }

  @override
  Future<String> signSolanaTransaction(dynamic transaction) async {
    if (!isConnected) {
      throw const WalletException(
        message: 'Not connected to Phantom',
        code: 'NOT_CONNECTED',
      );
    }

    // Serialize and encode transaction
    // In production, would use solana package to serialize
    final serializedTx = base64Encode(utf8.encode(transaction.toString()));

    final signUrl = '${WalletConstants.phantomConnectUrl}/signTransaction'
        '?session=${Uri.encodeComponent(_session ?? '')}'
        '&transaction=$serializedTx';

    await launchUrl(
      Uri.parse(signUrl),
      mode: LaunchMode.externalApplication,
    );

    throw const WalletException(
      message: 'Transaction signing requires deep link callback',
      code: 'NOT_IMPLEMENTED',
    );
  }

  @override
  Future<List<String>> signAllTransactions(List<dynamic> transactions) async {
    if (!isConnected) {
      throw const WalletException(
        message: 'Not connected to Phantom',
        code: 'NOT_CONNECTED',
      );
    }

    // Serialize all transactions
    final serializedTxs = transactions
        .map((tx) => base64Encode(utf8.encode(tx.toString())))
        .join(',');

    final signUrl = '${WalletConstants.phantomConnectUrl}/signAllTransactions'
        '?session=${Uri.encodeComponent(_session ?? '')}'
        '&transactions=$serializedTxs';

    await launchUrl(
      Uri.parse(signUrl),
      mode: LaunchMode.externalApplication,
    );

    throw const WalletException(
      message: 'Batch transaction signing requires deep link callback',
      code: 'NOT_IMPLEMENTED',
    );
  }

  @override
  Future<String> signAndSendTransaction(dynamic transaction) async {
    if (!isConnected) {
      throw const WalletException(
        message: 'Not connected to Phantom',
        code: 'NOT_CONNECTED',
      );
    }

    final serializedTx = base64Encode(utf8.encode(transaction.toString()));

    final signUrl = '${WalletConstants.phantomConnectUrl}/signAndSendTransaction'
        '?session=${Uri.encodeComponent(_session ?? '')}'
        '&transaction=$serializedTx';

    await launchUrl(
      Uri.parse(signUrl),
      mode: LaunchMode.externalApplication,
    );

    throw const WalletException(
      message: 'Sign and send requires deep link callback',
      code: 'NOT_IMPLEMENTED',
    );
  }

  @override
  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _connectionController.close();
  }
}
