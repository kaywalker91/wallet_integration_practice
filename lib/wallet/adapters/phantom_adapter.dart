import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:pinenacl/api.dart';
import 'package:pinenacl/tweetnacl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/data/datasources/local/wallet_local_datasource.dart';
import 'package:wallet_integration_practice/data/models/phantom_session_model.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';

/// Types of signing operations for Phantom callback routing
enum SigningOperationType {
  signMessage,
  signTransaction,
  signAllTransactions,
  signAndSendTransaction,
}

/// Phantom wallet adapter for Solana
class PhantomAdapter extends SolanaWalletAdapter {
  /// Constructor with optional dependency injection
  PhantomAdapter({WalletLocalDataSource? localDataSource})
      : _localDataSource = localDataSource;

  /// Local data source for session persistence
  WalletLocalDataSource? _localDataSource;

  bool _isInitialized = false;
  String? _connectedAddress;
  String? _session;
  String? _currentCluster;

  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();

  // Phantom deep link response handling
  StreamSubscription? _linkSubscription;

  // Completer for waiting on deep link callback
  Completer<WalletEntity>? _connectionCompleter;

  // Completer for signature operations
  Completer<String>? _signatureCompleter;

  // Completer for batch signature operations
  Completer<List<String>>? _batchSignatureCompleter;

  // Current pending signing operation type
  SigningOperationType? _pendingOperation;

  // Connection timeout duration
  static const _connectionTimeout = Duration(seconds: 60);

  // Signature operation timeout (longer than connection)
  static const _signatureTimeout = Duration(seconds: 120);

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

    // 1. Try to restore session from storage first
    final restored = await _tryRestoreFromStorage();
    if (restored) {
      AppLogger.wallet('Phantom session restored from storage');
      _isInitialized = true;
      return;
    }

    // 2. No saved session, generate new key pair
    _generateKeyPair();

    _isInitialized = true;
    AppLogger.wallet('Phantom adapter initialized');
  }

  /// Set local data source for session persistence
  void setLocalDataSource(WalletLocalDataSource dataSource) {
    _localDataSource = dataSource;
  }

  /// Try to restore session from secure storage
  /// Returns true if restoration was successful
  Future<bool> _tryRestoreFromStorage() async {
    if (_localDataSource == null) return false;

    try {
      final saved = await _localDataSource!.getPhantomSession();
      if (saved == null) {
        AppLogger.wallet('No saved Phantom session found');
        return false;
      }

      // Check if session is expired
      if (saved.toEntity().isExpired) {
        AppLogger.wallet('Phantom session expired, clearing');
        await _localDataSource!.clearPhantomSession();
        return false;
      }

      // Restore key pair from Base64
      final privateKeyBytes = base64Decode(saved.dappPrivateKeyBase64);
      _dappPrivateKey = PrivateKey(Uint8List.fromList(privateKeyBytes));
      _dappPublicKey = _dappPrivateKey!.publicKey;
      _phantomPublicKey = Uint8List.fromList(base64Decode(saved.phantomPublicKeyBase64));
      _session = saved.session;
      _connectedAddress = saved.connectedAddress;
      _currentCluster = saved.cluster;

      AppLogger.wallet('Phantom session restored', data: {
        'address': _connectedAddress,
        'cluster': _currentCluster,
      });

      return true;
    } catch (e, st) {
      AppLogger.e('Failed to restore Phantom session', e, st);
      // Clear corrupted data
      try {
        await _localDataSource!.clearPhantomSession();
      } catch (clearError) {
        AppLogger.w('Failed to clear corrupted Phantom session: $clearError');
      }
      return false;
    }
  }

  /// Save session for persistence after successful connection
  Future<void> _saveSessionForPersistence() async {
    if (_localDataSource == null) {
      AppLogger.wallet('No local data source, skipping session persistence');
      return;
    }

    if (_dappPrivateKey == null || _phantomPublicKey == null || _connectedAddress == null) {
      AppLogger.wallet('Missing required data for session persistence');
      return;
    }

    try {
      final now = DateTime.now();
      final session = PhantomSessionModel(
        dappPrivateKeyBase64: base64Encode(_dappPrivateKey!.toList()),
        dappPublicKeyBase64: base64Encode(_dappPublicKey!.toList()),
        phantomPublicKeyBase64: base64Encode(_phantomPublicKey!),
        session: _session ?? '',
        connectedAddress: _connectedAddress!,
        cluster: _currentCluster ?? ChainConstants.solanaMainnet,
        createdAt: now,
        lastUsedAt: now,
        expiresAt: now.add(const Duration(days: 7)),
      );

      await _localDataSource!.savePhantomSession(session);
      AppLogger.wallet('Phantom session saved for persistence');
    } catch (e, st) {
      AppLogger.e('Failed to save Phantom session', e, st);
    }
  }

  /// Restore session from storage and return wallet entity
  /// This method can be called without triggering a new connect() flow
  /// Returns null if no valid session is available
  ///
  /// Note: This method handles the case where setLocalDataSource() was called
  /// after initialize(). In that case, _tryRestoreFromStorage() would have
  /// returned false during initialize() because _localDataSource was null.
  /// We retry restoration here if localDataSource is now available.
  Future<WalletEntity?> restoreSession() async {
    if (!_isInitialized) {
      await initialize();
    }

    // Already connected - return immediately
    if (isConnected) {
      // Phase 2.3: Validate encryption keys before accepting restored session
      if (AppConstants.enablePhantomKeyValidation && !_validateEncryptionKeys()) {
        AppLogger.wallet('Phantom keys invalid during restoration, disconnecting');
        await disconnect();
        return null;
      }

      final wallet = WalletEntity(
        address: _connectedAddress!,
        type: walletType,
        cluster: _currentCluster,
        sessionTopic: _session,
        connectedAt: DateTime.now(),
      );

      _connectionController.add(WalletConnectionStatus.connected(wallet));

      // Update last used timestamp
      try {
        await _localDataSource?.updatePhantomSessionLastUsed();
      } catch (e) {
        AppLogger.w('Failed to update Phantom session last used timestamp: $e');
      }

      return wallet;
    }

    // Not connected yet - try to restore from storage if localDataSource is available
    // This handles the case where setLocalDataSource() was called after initialize()
    if (_localDataSource != null) {
      AppLogger.wallet('Attempting late session restoration from storage');
      final restored = await _tryRestoreFromStorage();

      if (restored && _connectedAddress != null) {
        // Phase 2.3: Validate encryption keys before accepting restored session
        if (AppConstants.enablePhantomKeyValidation && !_validateEncryptionKeys()) {
          AppLogger.wallet('Phantom keys invalid after late restoration, disconnecting');
          await disconnect();
          return null;
        }

        final wallet = WalletEntity(
          address: _connectedAddress!,
          type: walletType,
          cluster: _currentCluster,
          sessionTopic: _session,
          connectedAt: DateTime.now(),
        );

        _connectionController.add(WalletConnectionStatus.connected(wallet));

        AppLogger.wallet('Late session restoration successful', data: {
          'address': _connectedAddress,
          'cluster': _currentCluster,
        });

        return wallet;
      }
    }

    // No valid session available
    AppLogger.wallet('Phantom session restoration failed - no valid session');
    return null;
  }

  /// Phase 2.3: Validate Phantom encryption keys
  ///
  /// Returns true if encryption keys are valid and ready for signing.
  /// Checks that both dApp private key and Phantom public key are present
  /// and have the correct format.
  bool _validateEncryptionKeys() {
    if (_dappPrivateKey == null) {
      AppLogger.wallet('Phantom key validation failed: dApp private key is null');
      return false;
    }

    if (_phantomPublicKey == null) {
      AppLogger.wallet('Phantom key validation failed: Phantom public key is null');
      return false;
    }

    if (_phantomPublicKey!.length != 32) {
      AppLogger.wallet('Phantom key validation failed: public key has wrong length', data: {
        'expected': 32,
        'actual': _phantomPublicKey!.length,
      });
      return false;
    }

    return true;
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
      try {
        final wallet = await _connectionCompleter!.future.timeout(
          _connectionTimeout,
          onTimeout: () {
            // Clean up completer on timeout to prevent memory leak
            _connectionCompleter = null;
            throw const WalletException(
              message: '연결 시간이 초과되었습니다. Phantom 앱에서 연결을 승인해주세요.',
              code: 'CONNECTION_TIMEOUT',
            );
          },
        );
        return wallet;
      } catch (e) {
        // Ensure completer is cleaned up on any error during wait
        _connectionCompleter = null;
        rethrow;
      }
    } catch (e) {
      AppLogger.e('Phantom connection failed', e);
      _connectionController.add(WalletConnectionStatus.error(e.toString()));
      // Final cleanup in outer catch (defensive)
      _connectionCompleter = null;
      rethrow;
    }
  }

  /// Handle deep link callback from Phantom
  /// Routes to appropriate handler based on path
  Future<void> handleDeepLinkCallback(Uri uri) async {
    AppLogger.wallet('🔔 Handling Phantom callback', data: {
      'uri': uri.toString(),
      'scheme': uri.scheme,
      'host': uri.host,
      'path': uri.path,
    });

    // Extract path from the callback (format: iLityHub://phantom/signMessage)
    final path = uri.path.replaceFirst('/', ''); // Remove leading slash

    // Route to signature handler for signing operations
    if (path == 'signMessage' ||
        path == 'signTransaction' ||
        path == 'signAllTransactions' ||
        path == 'signAndSendTransaction') {
      await handleSignatureCallback(uri);
      return;
    }

    // Default: handle as connection callback
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

          // 1. Store Phantom's public key with validation
          _phantomPublicKey = _decodeBase58(phantomPublicKeyStr);
          if (_phantomPublicKey == null || _phantomPublicKey!.length != 32) {
            throw const WalletException(
              message: 'Invalid Phantom public key length',
              code: 'INVALID_PUBLIC_KEY',
            );
          }

          // 2. Decode nonce and data with validation
          final nonce = _decodeBase58(nonceStr);
          if (nonce.length != 24) {
            throw const WalletException(
              message: 'Invalid nonce length (expected 24 bytes)',
              code: 'INVALID_NONCE',
            );
          }

          final encryptedData = _decodeBase58(dataStr);
          if (encryptedData.isEmpty) {
            throw const WalletException(
              message: 'Empty encrypted data',
              code: 'EMPTY_DATA',
            );
          }

          // 3. Decrypt using TweetNaCl directly
          // We need private key bytes and their public key bytes
          final privateKeyBytes = Uint8List.fromList(_dappPrivateKey!);
          final theirPublicKeyBytes = _phantomPublicKey!;

          // Manual padding for TweetNaCl low-level API
          // boxzerobytes = 16 (prepended to ciphertext), zerobytes = 32 (stripped from plaintext)
          const boxZeroBytesLength = 16;
          const zeroBytesLength = 32;

          final c = Uint8List(boxZeroBytesLength + encryptedData.length);
          // First 16 bytes are 0 (default in Uint8List)
          c.setRange(boxZeroBytesLength, c.length, encryptedData);

          final m = Uint8List(c.length);

          // Call crypto_box_open with 6 arguments
          // The function modifies 'm' in place with decrypted data
          // It returns the output buffer (m) on success
          // Authentication failure will throw an exception internally
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

          // Find the actual end of the message (trim null bytes)
          var endIndex = messageBytes.length;
          while (endIndex > 0 && messageBytes[endIndex - 1] == 0) {
            endIndex--;
          }
          final trimmedBytes = messageBytes.sublist(0, endIndex);

          final decryptedString = utf8.decode(trimmedBytes);

          AppLogger.wallet('🔓 Decrypted Phantom payload', data: {'json': decryptedString});

          final payload = jsonDecode(decryptedString);

          // 4. Extract data with type checking
          if (payload is Map<String, dynamic>) {
            if (payload['public_key'] != null) {
              walletAddress = payload['public_key'] as String?;
            }
            if (payload['session'] != null) {
              _session = payload['session'] as String?;
            }
          } else {
            throw const WalletException(
              message: 'Invalid payload format from Phantom',
              code: 'INVALID_PAYLOAD',
            );
          }
        } catch (e) {
          AppLogger.e('Decryption failed', e);
          if (e is WalletException) rethrow;
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

        // Save session for persistence FIRST (blocking)
        // This ensures MultiSessionDataSource can access the session in _onConnectionChanged()
        await _saveSessionForPersistence();

        // Then complete the completer to unblock connect()
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

  /// Handle signature callback from Phantom
  /// Routes to appropriate completer based on pending operation type
  Future<void> handleSignatureCallback(Uri uri) async {
    AppLogger.wallet('🔔 Handling Phantom signature callback', data: {
      'uri': uri.toString(),
      'path': uri.path,
      'pendingOperation': _pendingOperation?.name,
    });

    try {
      final params = uri.queryParameters;

      // Check for error response
      if (params.containsKey('errorCode')) {
        final errorCode = params['errorCode'];
        final errorMessage = params['errorMessage'] ?? 'Signing cancelled';
        final error = WalletException(
          message: errorMessage,
          code: errorCode ?? 'SIGNING_ERROR',
        );
        _completeSigningWithError(error);
        return;
      }

      // Get encrypted response data
      final dataStr = params['data'];
      final nonceStr = params['nonce'];

      if (dataStr == null || nonceStr == null) {
        throw const WalletException(
          message: 'Missing signature data from Phantom',
          code: 'MISSING_DATA',
        );
      }

      // Decrypt the response
      final decryptedPayload = _decryptSignatureResponse(dataStr, nonceStr);

      AppLogger.wallet('🔓 Decrypted signature payload', data: {
        'keys': decryptedPayload.keys.toList(),
      });

      // Extract signature based on operation type
      switch (_pendingOperation) {
        case SigningOperationType.signMessage:
          final signature = decryptedPayload['signature'] as String?;
          if (signature == null) {
            throw const WalletException(
              message: 'No signature in response',
              code: 'NO_SIGNATURE',
            );
          }
          _signatureCompleter?.complete(signature);
          break;

        case SigningOperationType.signTransaction:
          final transaction = decryptedPayload['transaction'] as String?;
          if (transaction == null) {
            throw const WalletException(
              message: 'No signed transaction in response',
              code: 'NO_TRANSACTION',
            );
          }
          _signatureCompleter?.complete(transaction);
          break;

        case SigningOperationType.signAllTransactions:
          final transactions = decryptedPayload['transactions'] as List?;
          if (transactions == null) {
            throw const WalletException(
              message: 'No signed transactions in response',
              code: 'NO_TRANSACTIONS',
            );
          }
          final signedTxs = transactions.cast<String>().toList();
          _batchSignatureCompleter?.complete(signedTxs);
          break;

        case SigningOperationType.signAndSendTransaction:
          final txSignature = decryptedPayload['signature'] as String?;
          if (txSignature == null) {
            throw const WalletException(
              message: 'No transaction signature in response',
              code: 'NO_TX_SIGNATURE',
            );
          }
          _signatureCompleter?.complete(txSignature);
          break;

        case null:
          throw const WalletException(
            message: 'No pending signing operation',
            code: 'NO_PENDING_OPERATION',
          );
      }

      // Clean up
      _pendingOperation = null;
      _signatureCompleter = null;
      _batchSignatureCompleter = null;

      AppLogger.wallet('✅ Signature callback handled successfully');
    } catch (e) {
      AppLogger.e('Error handling signature callback', e);
      _completeSigningWithError(e is WalletException
          ? e
          : WalletException(
              message: 'Signature callback failed: $e',
              code: 'CALLBACK_FAILED',
            ));
    }
  }

  /// Decrypt signature response from Phantom
  Map<String, dynamic> _decryptSignatureResponse(String dataStr, String nonceStr) {
    if (_dappPrivateKey == null || _phantomPublicKey == null) {
      throw const WalletException(
        message: 'Encryption keys not available',
        code: 'KEYS_NOT_AVAILABLE',
      );
    }

    // Decode nonce and data
    final nonce = _decodeBase58(nonceStr);
    if (nonce.length != 24) {
      throw const WalletException(
        message: 'Invalid nonce length',
        code: 'INVALID_NONCE',
      );
    }

    final encryptedData = _decodeBase58(dataStr);
    if (encryptedData.isEmpty) {
      throw const WalletException(
        message: 'Empty encrypted data',
        code: 'EMPTY_DATA',
      );
    }

    // Decrypt using TweetNaCl
    const boxZeroBytesLength = 16;
    const zeroBytesLength = 32;

    final c = Uint8List(boxZeroBytesLength + encryptedData.length);
    c.setRange(boxZeroBytesLength, c.length, encryptedData);

    final m = Uint8List(c.length);

    final privateKeyBytes = Uint8List.fromList(_dappPrivateKey!);
    final theirPublicKeyBytes = _phantomPublicKey!;

    TweetNaCl.crypto_box_open(
      m,
      c,
      c.length,
      nonce,
      theirPublicKeyBytes,
      privateKeyBytes,
    );

    // Extract message (skip zerobytes prefix)
    final messageBytes = m.sublist(zeroBytesLength);

    // Trim null bytes
    var endIndex = messageBytes.length;
    while (endIndex > 0 && messageBytes[endIndex - 1] == 0) {
      endIndex--;
    }
    final trimmedBytes = messageBytes.sublist(0, endIndex);

    final decryptedString = utf8.decode(trimmedBytes);
    return jsonDecode(decryptedString) as Map<String, dynamic>;
  }

  /// Complete pending signing operation with error
  void _completeSigningWithError(WalletException error) {
    if (_signatureCompleter != null && !_signatureCompleter!.isCompleted) {
      _signatureCompleter!.completeError(error);
    }
    if (_batchSignatureCompleter != null && !_batchSignatureCompleter!.isCompleted) {
      _batchSignatureCompleter!.completeError(error);
    }
    _pendingOperation = null;
    _signatureCompleter = null;
    _batchSignatureCompleter = null;
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
      'publicKey': '${publicKeyBase58.substring(0, 10)}...',
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

  /// Generate a random nonce for encryption (24 bytes)
  Uint8List _generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(24, (_) => random.nextInt(256)),
    );
  }

  /// Encrypt a payload for Phantom using X25519 shared secret
  /// Returns a map with 'nonce' and 'payload' in Base58 encoding
  Map<String, String> _encryptPayload(Map<String, dynamic> data) {
    if (_dappPrivateKey == null || _phantomPublicKey == null) {
      throw const WalletException(
        message: 'Encryption keys not available. Please reconnect.',
        code: 'ENCRYPTION_KEYS_MISSING',
      );
    }

    // Convert payload to JSON bytes
    final jsonString = jsonEncode(data);
    final messageBytes = utf8.encode(jsonString);

    // Generate a fresh nonce
    final nonce = _generateNonce();

    // Prepare for TweetNaCl encryption
    // zerobytes = 32 bytes of zeros prepended to message
    // boxzerobytes = 16 bytes that will be stripped from output
    const zeroBytesLength = 32;
    const boxZeroBytesLength = 16;

    // Pad message with zeros
    final m = Uint8List(zeroBytesLength + messageBytes.length);
    m.setRange(zeroBytesLength, m.length, messageBytes);

    final c = Uint8List(m.length);

    // Encrypt using crypto_box
    final privateKeyBytes = Uint8List.fromList(_dappPrivateKey!);
    final theirPublicKeyBytes = _phantomPublicKey!;

    TweetNaCl.crypto_box(
      c,
      m,
      m.length,
      nonce,
      theirPublicKeyBytes,
      privateKeyBytes,
    );

    // Remove the boxzerobytes prefix (first 16 bytes are zeros after encryption)
    final encryptedData = c.sublist(boxZeroBytesLength);

    return {
      'nonce': _encodeBase58(nonce),
      'payload': _encodeBase58(encryptedData),
    };
  }

  /// Build an encrypted signing request URL for Phantom
  String _buildSigningUrl({
    required String endpoint,
    required Map<String, dynamic> payload,
  }) {
    // Ensure we have the keys
    if (_dappPublicKey == null) {
      throw const WalletException(
        message: 'DApp public key not available',
        code: 'KEY_NOT_AVAILABLE',
      );
    }

    // Encrypt the payload
    final encrypted = _encryptPayload(payload);

    // Build the redirect link
    final redirectLink = Uri.encodeComponent(
      '${AppConstants.deepLinkScheme}://phantom/$endpoint',
    );

    // Build the URL with encrypted parameters
    final publicKeyBase58 = _encodeBase58(_dappPublicKey!.asTypedList);

    return 'phantom://v1/$endpoint'
        '?dapp_encryption_public_key=$publicKeyBase58'
        '&nonce=${encrypted['nonce']}'
        '&payload=${encrypted['payload']}'
        '&redirect_link=$redirectLink';
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

    // Clear persisted session (non-blocking)
    unawaited(_localDataSource?.clearPhantomSession().catchError((e) {
      AppLogger.e('Failed to clear Phantom session', e);
    }));

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

    if (_phantomPublicKey == null || _session == null) {
      throw const WalletException(
        message: 'Session not established. Please reconnect.',
        code: 'NO_SESSION',
      );
    }

    AppLogger.wallet('📝 Requesting Phantom message signature', data: {
      'messageLength': message.length,
      'address': address,
    });

    // Build encrypted payload with message as Base58
    final messageBytes = utf8.encode(message);
    final messageBase58 = _encodeBase58(Uint8List.fromList(messageBytes));

    final payload = {
      'session': _session,
      'message': messageBase58,
    };

    // Build signing URL
    final signUrl = _buildSigningUrl(
      endpoint: 'signMessage',
      payload: payload,
    );

    // Set up completer for async callback
    _signatureCompleter = Completer<String>();
    _pendingOperation = SigningOperationType.signMessage;

    try {
      // Launch Phantom
      final launched = await launchUrl(
        Uri.parse(signUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _completeSigningWithError(const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        ));
        throw const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        );
      }

      // Wait for callback with timeout
      final signature = await _signatureCompleter!.future.timeout(
        _signatureTimeout,
        onTimeout: () {
          _completeSigningWithError(const WalletException(
            message: '서명 시간이 초과되었습니다. Phantom 앱에서 서명을 승인해주세요.',
            code: 'SIGNATURE_TIMEOUT',
          ));
          throw const WalletException(
            message: '서명 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          );
        },
      );

      AppLogger.wallet('✅ Message signed successfully');
      return signature;
    } catch (e) {
      // Clean up on any error
      _pendingOperation = null;
      _signatureCompleter = null;
      rethrow;
    }
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

    if (_phantomPublicKey == null || _session == null) {
      throw const WalletException(
        message: 'Session not established. Please reconnect.',
        code: 'NO_SESSION',
      );
    }

    AppLogger.wallet('📝 Requesting Phantom transaction signature');

    // Serialize transaction to bytes and encode as Base58
    // Expects transaction to be either Uint8List or serializable
    Uint8List txBytes;
    if (transaction is Uint8List) {
      txBytes = transaction;
    } else if (transaction is List<int>) {
      txBytes = Uint8List.fromList(transaction);
    } else {
      // Fallback: encode as UTF-8 string
      txBytes = Uint8List.fromList(utf8.encode(transaction.toString()));
    }

    final transactionBase58 = _encodeBase58(txBytes);

    final payload = {
      'session': _session,
      'transaction': transactionBase58,
    };

    // Build signing URL
    final signUrl = _buildSigningUrl(
      endpoint: 'signTransaction',
      payload: payload,
    );

    // Set up completer for async callback
    _signatureCompleter = Completer<String>();
    _pendingOperation = SigningOperationType.signTransaction;

    try {
      // Launch Phantom
      final launched = await launchUrl(
        Uri.parse(signUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _completeSigningWithError(const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        ));
        throw const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        );
      }

      // Wait for callback with timeout
      final signedTransaction = await _signatureCompleter!.future.timeout(
        _signatureTimeout,
        onTimeout: () {
          _completeSigningWithError(const WalletException(
            message: '트랜잭션 서명 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          ));
          throw const WalletException(
            message: '트랜잭션 서명 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          );
        },
      );

      AppLogger.wallet('✅ Transaction signed successfully');
      return signedTransaction;
    } catch (e) {
      _pendingOperation = null;
      _signatureCompleter = null;
      rethrow;
    }
  }

  @override
  Future<List<String>> signAllTransactions(List<dynamic> transactions) async {
    if (!isConnected) {
      throw const WalletException(
        message: 'Not connected to Phantom',
        code: 'NOT_CONNECTED',
      );
    }

    if (_phantomPublicKey == null || _session == null) {
      throw const WalletException(
        message: 'Session not established. Please reconnect.',
        code: 'NO_SESSION',
      );
    }

    AppLogger.wallet('📝 Requesting Phantom batch transaction signature', data: {
      'count': transactions.length,
    });

    // Serialize each transaction to Base58
    final transactionsBase58 = transactions.map((tx) {
      Uint8List txBytes;
      if (tx is Uint8List) {
        txBytes = tx;
      } else if (tx is List<int>) {
        txBytes = Uint8List.fromList(tx);
      } else {
        txBytes = Uint8List.fromList(utf8.encode(tx.toString()));
      }
      return _encodeBase58(txBytes);
    }).toList();

    final payload = {
      'session': _session,
      'transactions': transactionsBase58,
    };

    // Build signing URL
    final signUrl = _buildSigningUrl(
      endpoint: 'signAllTransactions',
      payload: payload,
    );

    // Set up completer for async callback
    _batchSignatureCompleter = Completer<List<String>>();
    _pendingOperation = SigningOperationType.signAllTransactions;

    try {
      // Launch Phantom
      final launched = await launchUrl(
        Uri.parse(signUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _completeSigningWithError(const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        ));
        throw const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        );
      }

      // Wait for callback with timeout
      final signedTransactions = await _batchSignatureCompleter!.future.timeout(
        _signatureTimeout,
        onTimeout: () {
          _completeSigningWithError(const WalletException(
            message: '배치 트랜잭션 서명 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          ));
          throw const WalletException(
            message: '배치 트랜잭션 서명 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          );
        },
      );

      AppLogger.wallet('✅ Batch transactions signed successfully', data: {
        'count': signedTransactions.length,
      });
      return signedTransactions;
    } catch (e) {
      _pendingOperation = null;
      _batchSignatureCompleter = null;
      rethrow;
    }
  }

  @override
  Future<String> signAndSendTransaction(dynamic transaction) async {
    if (!isConnected) {
      throw const WalletException(
        message: 'Not connected to Phantom',
        code: 'NOT_CONNECTED',
      );
    }

    if (_phantomPublicKey == null || _session == null) {
      throw const WalletException(
        message: 'Session not established. Please reconnect.',
        code: 'NO_SESSION',
      );
    }

    AppLogger.wallet('📝 Requesting Phantom sign and send transaction');

    // Serialize transaction to bytes and encode as Base58
    Uint8List txBytes;
    if (transaction is Uint8List) {
      txBytes = transaction;
    } else if (transaction is List<int>) {
      txBytes = Uint8List.fromList(transaction);
    } else {
      txBytes = Uint8List.fromList(utf8.encode(transaction.toString()));
    }

    final transactionBase58 = _encodeBase58(txBytes);

    final payload = {
      'session': _session,
      'transaction': transactionBase58,
    };

    // Build signing URL
    final signUrl = _buildSigningUrl(
      endpoint: 'signAndSendTransaction',
      payload: payload,
    );

    // Set up completer for async callback
    _signatureCompleter = Completer<String>();
    _pendingOperation = SigningOperationType.signAndSendTransaction;

    try {
      // Launch Phantom
      final launched = await launchUrl(
        Uri.parse(signUrl),
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _completeSigningWithError(const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        ));
        throw const WalletException(
          message: 'Failed to open Phantom wallet',
          code: 'LAUNCH_FAILED',
        );
      }

      // Wait for callback with timeout
      final txSignature = await _signatureCompleter!.future.timeout(
        _signatureTimeout,
        onTimeout: () {
          _completeSigningWithError(const WalletException(
            message: '트랜잭션 전송 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          ));
          throw const WalletException(
            message: '트랜잭션 전송 시간이 초과되었습니다.',
            code: 'SIGNATURE_TIMEOUT',
          );
        },
      );

      AppLogger.wallet('✅ Transaction sent successfully', data: {
        'signature': txSignature.length > 20
            ? '${txSignature.substring(0, 20)}...'
            : txSignature,
      });
      return txSignature;
    } catch (e) {
      _pendingOperation = null;
      _signatureCompleter = null;
      rethrow;
    }
  }

  // ============================================================
  // SIWS (Sign In With Solana) Support
  // ============================================================

  /// Generate a SIWS (Sign In With Solana) message
  /// Following the Sign-In With Solana specification
  ///
  /// Example output:
  /// ```
  /// example.com wants you to sign in with your Solana account:
  /// 5K7...abc
  ///
  /// I accept the Terms of Service
  ///
  /// URI: https://example.com
  /// Version: 1
  /// Chain ID: mainnet
  /// Nonce: abc123
  /// Issued At: 2024-01-01T00:00:00.000Z
  /// ```
  String generateSiwsMessage({
    required String domain,
    required String address,
    String? statement,
    String? uri,
    String version = '1',
    String? chainId,
    String? nonce,
    DateTime? issuedAt,
    DateTime? expirationTime,
    DateTime? notBefore,
    String? requestId,
    List<String>? resources,
  }) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('$domain wants you to sign in with your Solana account:');
    buffer.writeln(address);
    buffer.writeln();

    // Statement (optional)
    if (statement != null && statement.isNotEmpty) {
      buffer.writeln(statement);
      buffer.writeln();
    }

    // URI (optional but recommended)
    if (uri != null) {
      buffer.writeln('URI: $uri');
    }

    // Version (required)
    buffer.writeln('Version: $version');

    // Chain ID (optional, Solana-specific: mainnet-beta, devnet, testnet)
    if (chainId != null) {
      buffer.writeln('Chain ID: $chainId');
    }

    // Nonce (recommended for replay protection)
    if (nonce != null) {
      buffer.writeln('Nonce: $nonce');
    }

    // Issued At (optional)
    final issued = issuedAt ?? DateTime.now();
    buffer.writeln('Issued At: ${issued.toUtc().toIso8601String()}');

    // Expiration Time (optional)
    if (expirationTime != null) {
      buffer.writeln('Expiration Time: ${expirationTime.toUtc().toIso8601String()}');
    }

    // Not Before (optional)
    if (notBefore != null) {
      buffer.writeln('Not Before: ${notBefore.toUtc().toIso8601String()}');
    }

    // Request ID (optional)
    if (requestId != null) {
      buffer.writeln('Request ID: $requestId');
    }

    // Resources (optional)
    if (resources != null && resources.isNotEmpty) {
      buffer.writeln('Resources:');
      for (final resource in resources) {
        buffer.writeln('- $resource');
      }
    }

    return buffer.toString().trimRight();
  }

  /// Verify an Ed25519 signature from Solana
  ///
  /// [message] - The original message that was signed (UTF-8 string)
  /// [signatureBase58] - The signature in Base58 encoding (64 bytes when decoded)
  /// [publicKeyBase58] - The signer's public key in Base58 encoding (32 bytes when decoded)
  ///
  /// Returns true if the signature is valid, false otherwise
  bool verifySolanaSignature({
    required String message,
    required String signatureBase58,
    required String publicKeyBase58,
  }) {
    try {
      // Decode the signature (should be 64 bytes)
      final signature = _decodeBase58(signatureBase58);
      if (signature.length != 64) {
        AppLogger.wallet('Invalid signature length', data: {
          'expected': 64,
          'actual': signature.length,
        });
        return false;
      }

      // Decode the public key (should be 32 bytes)
      final publicKey = _decodeBase58(publicKeyBase58);
      if (publicKey.length != 32) {
        AppLogger.wallet('Invalid public key length', data: {
          'expected': 32,
          'actual': publicKey.length,
        });
        return false;
      }

      // Convert message to bytes
      final messageBytes = Uint8List.fromList(utf8.encode(message));

      // Verify using TweetNaCl Ed25519 signature verification
      // crypto_sign_open verifies the signature
      // The signed message format is: signature (64 bytes) + message
      final signedMessage = Uint8List(signature.length + messageBytes.length);
      signedMessage.setRange(0, signature.length, signature);
      signedMessage.setRange(signature.length, signedMessage.length, messageBytes);

      final openedMessage = Uint8List(signedMessage.length);

      // TweetNaCl.crypto_sign_open signature:
      // (Uint8List m, int dummy, Uint8List sm, int smoff, int n, Uint8List pk)
      // Returns message length on success, or -1 on failure
      final result = TweetNaCl.crypto_sign_open(
        openedMessage,  // output buffer
        -1,             // dummy (not used)
        signedMessage,  // signed message (signature + message)
        0,              // offset in signed message
        signedMessage.length,  // length of signed message
        publicKey,      // public key
      );

      if (result < 0) {
        AppLogger.wallet('Signature verification failed');
        return false;
      }

      AppLogger.wallet('✅ Signature verified successfully');
      return true;
    } catch (e) {
      AppLogger.e('Error verifying signature', e);
      return false;
    }
  }

  /// Perform SIWS authentication flow
  ///
  /// This is a convenience method that:
  /// 1. Generates a SIWS message
  /// 2. Requests signature from Phantom
  /// 3. Verifies the signature
  ///
  /// Returns the signature if successful, throws on failure
  Future<String> signInWithSolana({
    required String domain,
    String? statement,
    String? uri,
    String? nonce,
    Duration? expiresIn,
  }) async {
    if (!isConnected || _connectedAddress == null) {
      throw const WalletException(
        message: 'Wallet not connected',
        code: 'NOT_CONNECTED',
      );
    }

    // Generate SIWS message
    final now = DateTime.now();
    final message = generateSiwsMessage(
      domain: domain,
      address: _connectedAddress!,
      statement: statement ?? 'Sign in to $domain',
      uri: uri ?? 'https://$domain',
      chainId: _currentCluster ?? 'mainnet-beta',
      nonce: nonce ?? _generateRandomNonce(),
      issuedAt: now,
      expirationTime: expiresIn != null ? now.add(expiresIn) : null,
    );

    AppLogger.wallet('📝 SIWS message generated', data: {
      'domain': domain,
      'address': _connectedAddress,
      'messageLength': message.length,
    });

    // Request signature
    final signature = await personalSign(message, _connectedAddress!);

    // Verify the signature
    final isValid = verifySolanaSignature(
      message: message,
      signatureBase58: signature,
      publicKeyBase58: _connectedAddress!,
    );

    if (!isValid) {
      throw const WalletException(
        message: 'SIWS signature verification failed',
        code: 'SIWS_VERIFICATION_FAILED',
      );
    }

    AppLogger.wallet('✅ SIWS authentication successful');
    return signature;
  }

  /// Generate a random nonce for SIWS
  String _generateRandomNonce() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    return _encodeBase58(Uint8List.fromList(bytes));
  }

  @override
  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _connectionController.close();
  }
}
