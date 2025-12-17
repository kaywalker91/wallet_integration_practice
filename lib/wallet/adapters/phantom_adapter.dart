import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pinenacl/api.dart';
import 'package:pinenacl/tweetnacl.dart';
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

  // Completer for waiting on deep link callback
  Completer<WalletEntity>? _connectionCompleter;

  // Connection timeout duration
  static const _connectionTimeout = Duration(seconds: 60);

  // X25519 key pair for Phantom encryption
  PrivateKey? _dappPrivateKey;
  PublicKey? _dappPublicKey;
  Uint8List? _phantomPublicKey; // Received from Phantom

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

    // Generate X25519 key pair for Phantom encryption
    _generateKeyPair();

    _isInitialized = true;
    AppLogger.wallet('Phantom adapter initialized');
  }

  /// Generate X25519 key pair for Phantom deep link encryption
  void _generateKeyPair() {
    // Generate a new X25519 private key
    _dappPrivateKey = PrivateKey.generate();
    _dappPublicKey = _dappPrivateKey!.publicKey;

    AppLogger.wallet('Generated X25519 key pair for Phantom encryption');
  }

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    if (!_isInitialized) {
      await initialize();
    }

    _connectionController.add(WalletConnectionStatus.connecting());
    _currentCluster = cluster ?? ChainConstants.solanaMainnet;

    try {
      // Check if Phantom is installed using deep link scheme
      final phantomSchemeUri = Uri.parse('phantom://');
      final isInstalled = await canLaunchUrl(phantomSchemeUri);

      if (!isInstalled) {
        throw WalletNotInstalledException(
          walletType: walletType.name,
          message: 'Phantom wallet is not installed',
        );
      }

      // Build Phantom connect deep link
      final connectUrl = _buildConnectUrl();

      // Launch Phantom app
      final launched = await launchUrl(
        Uri.parse(connectUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        );
      }

      AppLogger.wallet('Phantom connect requested', data: {'cluster': _currentCluster});

      // Create completer to wait for deep link callback
      _connectionCompleter = Completer<WalletEntity>();

      // Wait for the deep link callback with timeout
      final wallet = await _connectionCompleter!.future.timeout(
        _connectionTimeout,
        onTimeout: () {
          throw const WalletException(
            message: '연결 시간이 초과되었습니다. Phantom 앱에서 연결을 승인해주세요.',
            code: 'CONNECTION_TIMEOUT',
          );
        },
      );

      return wallet;
    } catch (e) {
      AppLogger.e('Phantom connection failed', e);
      _connectionController.add(WalletConnectionStatus.error(e.toString()));
      _connectionCompleter = null;
      rethrow;
    }
  }

  /// Handle deep link callback from Phantom
  Future<void> handleDeepLinkCallback(Uri uri) async {
    AppLogger.wallet('🔔 Handling Phantom callback', data: {
      'uri': uri.toString(),
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
    });

    try {
      // Parse the callback parameters
      final params = uri.queryParameters;
      AppLogger.wallet('📦 Phantom callback params', data: {
        'paramKeys': params.keys.toList(),
        'hasErrorCode': params.containsKey('errorCode'),
        'hasPublicKey': params.containsKey('phantom_encryption_public_key') || params.containsKey('public_key'),
        'hasData': params.containsKey('data'),
        'hasNonce': params.containsKey('nonce'),
      });

      if (params.containsKey('errorCode')) {
        final errorCode = params['errorCode'];
        final errorMessage = params['errorMessage'] ?? 'Unknown error';
        final error = WalletException(
          message: errorMessage,
          code: errorCode ?? 'PHANTOM_ERROR',
        );
        _connectionCompleter?.completeError(error);
        _connectionCompleter = null;
        _connectionController.add(WalletConnectionStatus.error(errorMessage));
        return;
      }

      // Extract the public key (wallet address)
      // Phantom returns 'phantom_encryption_public_key' for encrypted responses
      // or direct 'public_key' for some callbacks
      final phantomPublicKeyStr = params['phantom_encryption_public_key'];
      final publicKeyStr = params['public_key'];
      final dataStr = params['data'];
      final nonceStr = params['nonce'];

      String? walletAddress;
      
      // Handle Encrypted Response (Standard for Connect)
      if (phantomPublicKeyStr != null && dataStr != null && nonceStr != null) {
        AppLogger.wallet('🔐 Processing encrypted Phantom response...');
        
        try {
          if (_dappPrivateKey == null) {
             throw const WalletException(message: 'Key pair lost during connection', code: 'KEY_LOST');
          }

          // 1. Store Phantom's public key
          _phantomPublicKey = _decodeBase58(phantomPublicKeyStr);
          
          // 2. Decode nonce and data
          final nonce = _decodeBase58(nonceStr);
          final encryptedData = _decodeBase58(dataStr);
          
          // 3. Decrypt using TweetNaCl directly
          // We need private key bytes and their public key bytes
          final privateKeyBytes = Uint8List.fromList(_dappPrivateKey!);
          final theirPublicKeyBytes = _phantomPublicKey!;

          // Manual padding for TweetNaCl low-level API
          // boxzerobytes = 16, zerobytes = 32
          const boxZeroBytesLength = 16;
          const zeroBytesLength = 32;

          final c = Uint8List(boxZeroBytesLength + encryptedData.length);
          // First 16 bytes are 0 (default in Uint8List)
          c.setRange(boxZeroBytesLength, c.length, encryptedData);

          final m = Uint8List(c.length);

          // Call crypto_box_open with 6 arguments
          // crypto_box_open(m, c, d, n, pk, sk)
          TweetNaCl.crypto_box_open(
            m,
            c,
            c.length,
            nonce,
            theirPublicKeyBytes,
            privateKeyBytes,
          );

          // Result is in m, starting at offset 32 (zeroBytesLength)
          
          final messageBytes = m.sublist(zeroBytesLength);
          final decryptedString = utf8.decode(messageBytes);
          
          AppLogger.wallet('🔓 Decrypted Phantom payload', data: {'json': decryptedString});
          
          final payload = jsonDecode(decryptedString);
          
          // 4. Extract data
          if (payload['public_key'] != null) {
            walletAddress = payload['public_key'];
          }
          if (payload['session'] != null) {
            _session = payload['session'];
          }
        } catch (e) {
          AppLogger.e('Decryption failed', e);
          throw WalletException(
            message: 'Phantom 응답을 복호화하는데 실패했습니다: $e',
            code: 'DECRYPTION_FAILED',
          );
        }
      } 
      // Handle Plaintext Response (Legacy/Fallback)
      else if (publicKeyStr != null) {
        walletAddress = publicKeyStr;
        AppLogger.wallet('Received plaintext public key');
      }

      if (walletAddress != null && walletAddress.isNotEmpty) {
        _connectedAddress = walletAddress;
        
        // Session fallback if not in payload (sometimes in query params directly?)
        if (_session == null && params.containsKey('session')) {
          _session = params['session'];
        }

        final wallet = WalletEntity(
          address: _connectedAddress!,
          type: walletType,
          cluster: _currentCluster,
          sessionTopic: _session,
          connectedAt: DateTime.now(),
        );

        // Complete the completer to unblock connect()
        _connectionCompleter?.complete(wallet);
        _connectionCompleter = null;

        _connectionController.add(WalletConnectionStatus.connected(wallet));
        AppLogger.wallet('Phantom connected', data: {'address': _connectedAddress});
      } else {
        throw const WalletException(
          message: 'Phantom에서 지갑 주소를 받지 못했습니다',
          code: 'NO_ADDRESS',
        );
      }
    } catch (e) {
      AppLogger.e('Error handling Phantom callback', e);
      _connectionCompleter?.completeError(e);
      _connectionCompleter = null;
      _connectionController.add(WalletConnectionStatus.error(e.toString()));
    }
  }

  String _buildConnectUrl() {
    // Ensure key pair is generated
    if (_dappPublicKey == null) {
      _generateKeyPair();
    }

    // Encode public key as Base58
    final publicKeyBase58 = _encodeBase58(_dappPublicKey!.asTypedList);

    final redirectLink = Uri.encodeComponent(
      '${AppConstants.deepLinkScheme}://phantom/callback',
    );
    final cluster = Uri.encodeComponent(_currentCluster ?? 'mainnet-beta');

    AppLogger.wallet('Building Phantom connect URL', data: {
      'publicKey': publicKeyBase58.substring(0, 10) + '...',
      'redirectLink': redirectLink,
      'cluster': cluster,
    });

    // Use phantom:// custom scheme for direct app invocation
    // Note: 'ul' path is only for Universal Links (HTTPS), not custom schemes
    return 'phantom://v1/connect'
        '?app_url=${Uri.encodeComponent(AppConstants.appUrl)}'
        '&dapp_encryption_public_key=$publicKeyBase58'
        '&redirect_link=$redirectLink'
        '&cluster=$cluster';
  }

  /// Base58 encoding for Solana/Phantom compatibility
  static const _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  String _encodeBase58(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    // Count leading zeros
    var leadingZeros = 0;
    for (final byte in bytes) {
      if (byte == 0) {
        leadingZeros++;
      } else {
        break;
      }
    }

    // Convert to base58
    final result = <int>[];
    var num = BigInt.zero;
    for (final byte in bytes) {
      num = (num << 8) + BigInt.from(byte);
    }

    while (num > BigInt.zero) {
      final remainder = (num % BigInt.from(58)).toInt();
      result.add(remainder);
      num = num ~/ BigInt.from(58);
    }

    // Add leading '1's for leading zeros in input
    final encoded = StringBuffer();
    for (var i = 0; i < leadingZeros; i++) {
      encoded.write('1');
    }

    // Append the converted digits in reverse order
    for (var i = result.length - 1; i >= 0; i--) {
      encoded.write(_base58Alphabet[result[i]]);
    }

    return encoded.toString();
  }

  /// Base58 decoding
  Uint8List _decodeBase58(String input) {
    if (input.isEmpty) return Uint8List(0);

    // Count leading '1's (zeros in the output)
    var leadingOnes = 0;
    for (final char in input.runes) {
      if (String.fromCharCode(char) == '1') {
        leadingOnes++;
      } else {
        break;
      }
    }

    // Convert from base58
    var num = BigInt.zero;
    for (final char in input.runes) {
      final index = _base58Alphabet.indexOf(String.fromCharCode(char));
      if (index < 0) {
        throw FormatException('Invalid Base58 character: ${String.fromCharCode(char)}');
      }
      num = num * BigInt.from(58) + BigInt.from(index);
    }

    // Convert BigInt to bytes
    final bytes = <int>[];
    while (num > BigInt.zero) {
      bytes.insert(0, (num & BigInt.from(0xFF)).toInt());
      num = num >> 8;
    }

    // Add leading zeros
    final result = Uint8List(leadingOnes + bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      result[leadingOnes + i] = bytes[i];
    }

    return result;
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

    // NOTE: We intentionally do NOT launch the Phantom disconnect URL here.
    // The disconnect URL (https://phantom.app/ul/v1/disconnect) opens a browser,
    // which can cause confusion when switching to another wallet like Trust Wallet.
    // The browser redirect to phantom.com was causing issues.
    // Instead, we just clear the local state. Phantom will handle session
    // cleanup on its side when a new connection is attempted.
    AppLogger.wallet('Phantom disconnect: clearing local state', data: {
      'hadSession': _session != null,
      'hadAddress': _connectedAddress != null,
    });

    _connectedAddress = null;
    _session = null;
    _phantomPublicKey = null;
    _connectionController.add(WalletConnectionStatus.disconnected());

    AppLogger.wallet('Phantom disconnected (local state cleared)');
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
