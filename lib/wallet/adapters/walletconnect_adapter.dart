import 'dart:async';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/domain/entities/transaction_entity.dart';
import 'package:wallet_integration_practice/domain/entities/session_account.dart';
import 'package:wallet_integration_practice/wallet/adapters/base_wallet_adapter.dart';
import 'package:wallet_integration_practice/wallet/models/wallet_adapter_config.dart';

/// WalletConnect v2 adapter implementation using Reown AppKit
///
/// Supports multiple accounts from a single wallet session.
/// The wallet (e.g., MetaMask) decides which accounts to share,
/// and this adapter manages which account is "active" for transactions.
class WalletConnectAdapter extends EvmWalletAdapter {
  final WalletAdapterConfig _config;

  ReownAppKit? _appKit;
  SessionData? _session;
  String? _uri;

  /// Manages multiple accounts from the session
  SessionAccounts _sessionAccounts = const SessionAccounts.empty();

  final _connectionController = StreamController<WalletConnectionStatus>.broadcast();

  /// Stream controller for account changes
  final _accountsChangedController = StreamController<SessionAccounts>.broadcast();

  WalletConnectAdapter({WalletAdapterConfig? config})
      : _config = config ?? WalletAdapterConfig.defaultConfig();

  /// Stream of account changes from the wallet
  Stream<SessionAccounts> get accountsChangedStream => _accountsChangedController.stream;

  /// Get current session accounts
  SessionAccounts get sessionAccounts => _sessionAccounts;

  /// Get the active account address for transactions
  String? get activeAddress => _sessionAccounts.activeAccount?.address;

  /// Check if session has multiple unique addresses
  bool get hasMultipleAccounts => _sessionAccounts.hasMultipleAddresses;

  @override
  WalletType get walletType => WalletType.walletConnect;

  @override
  bool get isInitialized => _appKit != null;

  @override
  bool get isConnected => _session != null;

  @override
  String? get connectedAddress {
    // Return active account address, or first account if no active set
    if (_sessionAccounts.isNotEmpty) {
      return activeAddress ?? _sessionAccounts.accounts.first.address;
    }

    // Fallback to parsing session directly
    if (_session == null) return null;
    try {
      final namespace = _session!.namespaces['eip155'];
      if (namespace == null || namespace.accounts.isEmpty) return null;
      final account = namespace.accounts.first;
      final parts = account.split(':');
      return parts.length >= 3 ? parts[2] : null;
    } catch (e) {
      AppLogger.e('Error getting connected address', e);
      return null;
    }
  }

  @override
  int? get currentChainId {
    if (_session == null) return null;
    try {
      final namespace = _session!.namespaces['eip155'];
      if (namespace == null || namespace.accounts.isEmpty) return null;
      final account = namespace.accounts.first;
      final parts = account.split(':');
      return parts.length >= 2 ? int.tryParse(parts[1]) : null;
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<WalletConnectionStatus> get connectionStream => _connectionController.stream;

  @override
  Future<void> initialize() async {
    if (_appKit != null) return;

    AppLogger.wallet('Initializing WalletConnect adapter');

    _appKit = await ReownAppKit.createInstance(
      projectId: _config.projectId,
      metadata: PairingMetadata(
        name: _config.appName,
        description: _config.appDescription,
        url: _config.appUrl,
        icons: [_config.appIcon],
        redirect: Redirect(
          native: '${AppConstants.deepLinkScheme}://',
          universal: 'https://${AppConstants.universalLinkHost}',
        ),
      ),
    );

    // Listen to session events
    _appKit!.onSessionConnect.subscribe(_onSessionConnect);
    _appKit!.onSessionDelete.subscribe(_onSessionDelete);
    _appKit!.onSessionEvent.subscribe(_onSessionEvent);
    _appKit!.onSessionUpdate.subscribe(_onSessionUpdate);

    // Restore existing sessions
    await _restoreSession();

    AppLogger.wallet('WalletConnect adapter initialized');
  }

  Future<void> _restoreSession() async {
    final sessions = _appKit!.sessions.getAll();
    if (sessions.isNotEmpty) {
      _session = sessions.first;
      _parseSessionAccounts();
      _emitConnectionStatus();
      AppLogger.wallet('Session restored', data: {
        'address': connectedAddress,
        'accountCount': _sessionAccounts.count,
      });
    }
  }

  void _onSessionConnect(SessionConnect? event) {
    if (event != null) {
      _session = event.session;
      _parseSessionAccounts();
      _emitConnectionStatus();
      AppLogger.wallet('Session connected', data: {
        'address': connectedAddress,
        'accountCount': _sessionAccounts.count,
        'hasMultipleAccounts': hasMultipleAccounts,
      });
    }
  }

  void _onSessionDelete(SessionDelete? event) {
    _session = null;
    _sessionAccounts = const SessionAccounts.empty();
    _connectionController.add(WalletConnectionStatus.disconnected());
    AppLogger.wallet('Session deleted');
  }

  /// Handle session events like accountsChanged and chainChanged
  void _onSessionEvent(SessionEvent? event) {
    if (event == null) return;

    AppLogger.wallet('Session event received', data: {
      'name': event.name,
      'topic': event.topic,
    });

    switch (event.name) {
      case 'accountsChanged':
        _handleAccountsChanged(event.data);
        break;
      case 'chainChanged':
        _handleChainChanged(event.data);
        break;
      default:
        AppLogger.wallet('Unhandled session event: ${event.name}');
    }
  }

  /// Handle session update (namespace changes)
  void _onSessionUpdate(SessionUpdate? event) {
    if (event == null) return;

    AppLogger.wallet('Session update received', data: {
      'topic': event.topic,
    });

    // Re-parse accounts from updated namespaces
    if (_session != null && _session!.topic == event.topic) {
      // Update session with new namespaces
      _session = _appKit!.sessions.get(event.topic);
      _parseSessionAccounts();
      _accountsChangedController.add(_sessionAccounts);
      _emitConnectionStatus();
    }
  }

  /// Handle accountsChanged event from wallet
  void _handleAccountsChanged(dynamic data) {
    AppLogger.wallet('Accounts changed', data: {'data': data});

    if (data is List) {
      // Data is typically a list of account strings
      final accountStrings = data.map((e) => e.toString()).toList();

      // Check if these are CAIP-10 format or just addresses
      if (accountStrings.isNotEmpty && accountStrings.first.contains(':')) {
        // CAIP-10 format
        _sessionAccounts = _sessionAccounts.updateAccounts(accountStrings);
      } else {
        // Just addresses - need to get full accounts from session
        _parseSessionAccounts();
      }

      _accountsChangedController.add(_sessionAccounts);
      _emitConnectionStatus();
    }
  }

  /// Handle chainChanged event from wallet
  void _handleChainChanged(dynamic data) {
    AppLogger.wallet('Chain changed', data: {'data': data});
    // Re-emit connection status with updated chain
    _emitConnectionStatus();
  }

  /// Parse accounts from current session namespaces
  void _parseSessionAccounts() {
    if (_session == null) {
      _sessionAccounts = const SessionAccounts.empty();
      return;
    }

    try {
      final namespace = _session!.namespaces['eip155'];
      if (namespace == null || namespace.accounts.isEmpty) {
        _sessionAccounts = const SessionAccounts.empty();
        return;
      }

      _sessionAccounts = SessionAccounts.fromNamespaceAccounts(namespace.accounts);

      AppLogger.wallet('Parsed session accounts', data: {
        'count': _sessionAccounts.count,
        'uniqueAddresses': _sessionAccounts.uniqueAddresses.length,
        'activeAddress': _sessionAccounts.activeAddress,
      });
    } catch (e) {
      AppLogger.e('Error parsing session accounts', e);
      _sessionAccounts = const SessionAccounts.empty();
    }
  }

  void _emitConnectionStatus() {
    if (_session != null && connectedAddress != null) {
      final wallet = WalletEntity(
        address: connectedAddress!,
        type: walletType,
        chainId: currentChainId,
        sessionTopic: _session!.topic,
        connectedAt: DateTime.now(),
        metadata: {
          'sessionAccounts': _sessionAccounts.accounts.map((a) => a.caip10Id).toList(),
          'hasMultipleAccounts': hasMultipleAccounts,
        },
      );
      _connectionController.add(WalletConnectionStatus.connected(wallet));
    }
  }

  /// Set the active account for transactions.
  ///
  /// The address must be one of the accounts approved in the session.
  /// Returns true if successful, false if address is not in session.
  bool setActiveAccount(String address) {
    if (!_sessionAccounts.containsAddress(address)) {
      AppLogger.w(
        'Cannot set active account: $address not in session. '
        'Available: ${_sessionAccounts.uniqueAddresses}',
      );
      return false;
    }

    _sessionAccounts = _sessionAccounts.setActiveAddress(address);
    _accountsChangedController.add(_sessionAccounts);
    _emitConnectionStatus();

    AppLogger.wallet('Active account changed', data: {
      'newActiveAddress': address,
    });

    return true;
  }

  /// Get all session accounts (for UI display)
  SessionAccounts getSessionAccounts() => _sessionAccounts;

  @override
  Future<WalletEntity> connect({int? chainId, String? cluster}) async {
    if (!isInitialized) {
      await initialize();
    }

    final targetChainId = chainId ?? 1; // Default to Ethereum mainnet
    final maxRetries = AppConstants.maxConnectionRetries;
    int retryCount = 0;

    _connectionController.add(WalletConnectionStatus.connecting(
      message: 'Initializing connection...',
      retryCount: 0,
      maxRetries: maxRetries,
    ));

    while (retryCount < maxRetries) {
      try {
        // Create namespace
        final requiredNamespaces = {
          'eip155': RequiredNamespace(
            chains: ['eip155:$targetChainId'],
            methods: _config.supportedMethods,
            events: _config.supportedEvents,
          ),
        };

        final optionalNamespaces = {
          'eip155': RequiredNamespace(
            chains: _config.supportedChainIds
                .map((id) => 'eip155:$id')
                .toList(),
            methods: _config.supportedMethods,
            events: _config.supportedEvents,
          ),
        };

        // Create connect response
        final connectResponse = await _appKit!.connect(
          requiredNamespaces: requiredNamespaces,
          optionalNamespaces: optionalNamespaces,
        );

        _uri = connectResponse.uri?.toString();

        AppLogger.wallet('Connection URI generated', data: {
          'uri': _uri,
          'attempt': retryCount + 1,
        });

        _connectionController.add(WalletConnectionStatus.connecting(
          message: 'Waiting for wallet approval...',
          retryCount: retryCount,
          maxRetries: maxRetries,
        ));

        // Wait for session approval
        _session = await connectResponse.session.future.timeout(
          AppConstants.connectionTimeout,
          onTimeout: () {
            throw WalletException(
              message: 'Connection timed out after ${AppConstants.connectionTimeout.inSeconds}s',
              code: 'TIMEOUT',
            );
          },
        );

        // Parse accounts from the approved session
        _parseSessionAccounts();

        if (connectedAddress == null) {
          throw const WalletException(
            message: 'Failed to get connected address',
            code: 'NO_ADDRESS',
          );
        }

        final wallet = WalletEntity(
          address: connectedAddress!,
          type: walletType,
          chainId: currentChainId,
          sessionTopic: _session!.topic,
          connectedAt: DateTime.now(),
          metadata: {
            'sessionAccounts': _sessionAccounts.accounts.map((a) => a.caip10Id).toList(),
            'hasMultipleAccounts': hasMultipleAccounts,
            'uniqueAddressCount': _sessionAccounts.uniqueAddresses.length,
          },
        );

        _connectionController.add(WalletConnectionStatus.connected(wallet));

        AppLogger.wallet('Wallet connected', data: {
          'address': wallet.address,
          'chainId': wallet.chainId,
          'attempts': retryCount + 1,
          'accountCount': _sessionAccounts.count,
          'hasMultipleAccounts': hasMultipleAccounts,
        });

        return wallet;

      } on WalletException catch (e) {
        retryCount++;
        AppLogger.w('Connection attempt $retryCount failed: ${e.message}');

        // Debug: Log retry condition evaluation
        final willRetry = e.code == 'TIMEOUT' && retryCount < maxRetries;
        AppLogger.wallet('Retry evaluation', data: {
          'errorCode': e.code,
          'retryCount': retryCount,
          'maxRetries': maxRetries,
          'willRetry': willRetry,
        });

        if (willRetry) {
          // Emit retry status
          _connectionController.add(WalletConnectionStatus.connecting(
            message: 'Retrying connection ($retryCount/$maxRetries)...',
            retryCount: retryCount,
            maxRetries: maxRetries,
          ));
          await Future.delayed(AppConstants.connectionRetryDelay);
          continue;
        }

        // Final failure
        AppLogger.e('Connection failed after $retryCount attempt(s)', e);
        _connectionController.add(WalletConnectionStatus.error(e.message));
        rethrow;

      } catch (e) {
        AppLogger.e('Unexpected connection error', e);
        _connectionController.add(WalletConnectionStatus.error(e.toString()));
        rethrow;
      }
    }

    // Max retries exceeded
    const exception = WalletException(
      message: 'Max connection retries exceeded',
      code: 'MAX_RETRIES',
    );
    _connectionController.add(WalletConnectionStatus.error(exception.message));
    throw exception;
  }

  @override
  Future<String?> getConnectionUri() async {
    return _uri;
  }

  @override
  Future<void> disconnect() async {
    if (_session == null) return;

    try {
      await _appKit!.disconnectSession(
        topic: _session!.topic,
        reason: ReownSignError(
          code: 6000,
          message: 'User disconnected',
        ),
      );
    } catch (e) {
      AppLogger.e('Error disconnecting', e);
    } finally {
      _session = null;
      _uri = null;
      _connectionController.add(WalletConnectionStatus.disconnected());
    }
  }

  @override
  Future<void> switchChain(int chainId) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:$chainId',
        request: SessionRequestParams(
          method: 'wallet_switchEthereumChain',
          params: [
            {'chainId': '0x${chainId.toRadixString(16)}'}
          ],
        ),
      );
    } catch (e) {
      AppLogger.e('Error switching chain', e);
      rethrow;
    }
  }

  @override
  Future<String> sendTransaction(TransactionRequest request) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      final result = await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${request.chainId}',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [request.toJson()],
        ),
      );

      AppLogger.tx('Transaction sent', txHash: result as String);
      return result;
    } catch (e) {
      AppLogger.e('Error sending transaction', e);
      rethrow;
    }
  }

  @override
  Future<String> personalSign(String message, String address) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      final result = await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${currentChainId ?? 1}',
        request: SessionRequestParams(
          method: 'personal_sign',
          params: [message, address],
        ),
      );

      AppLogger.wallet('Message signed', data: {'address': address});
      return result as String;
    } catch (e) {
      AppLogger.e('Error signing message', e);
      rethrow;
    }
  }

  @override
  Future<String> signTypedData(
    String address,
    Map<String, dynamic> typedData,
  ) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      final result = await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${currentChainId ?? 1}',
        request: SessionRequestParams(
          method: 'eth_signTypedData_v4',
          params: [address, typedData],
        ),
      );

      AppLogger.wallet('Typed data signed', data: {'address': address});
      return result as String;
    } catch (e) {
      AppLogger.e('Error signing typed data', e);
      rethrow;
    }
  }

  @override
  Future<List<String>> getAccounts() async {
    if (_session == null) return [];
    final namespace = _session!.namespaces['eip155'];
    if (namespace == null) return [];
    return namespace.accounts
        .map((account) => account.split(':').last)
        .toList();
  }

  @override
  Future<int> getChainId() async {
    return currentChainId ?? 1;
  }

  @override
  Future<void> addChain({
    required int chainId,
    required String chainName,
    required String rpcUrl,
    required String symbol,
    required int decimals,
    String? explorerUrl,
  }) async {
    if (_session == null) {
      throw const WalletException(
        message: 'No active session',
        code: 'NO_SESSION',
      );
    }

    try {
      await _appKit!.request(
        topic: _session!.topic,
        chainId: 'eip155:${currentChainId ?? 1}',
        request: SessionRequestParams(
          method: 'wallet_addEthereumChain',
          params: [
            {
              'chainId': '0x${chainId.toRadixString(16)}',
              'chainName': chainName,
              'rpcUrls': [rpcUrl],
              'nativeCurrency': {
                'name': symbol,
                'symbol': symbol,
                'decimals': decimals,
              },
              if (explorerUrl != null) 'blockExplorerUrls': [explorerUrl],
            }
          ],
        ),
      );
    } catch (e) {
      AppLogger.e('Error adding chain', e);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    _appKit?.onSessionConnect.unsubscribe(_onSessionConnect);
    _appKit?.onSessionDelete.unsubscribe(_onSessionDelete);
    _appKit?.onSessionEvent.unsubscribe(_onSessionEvent);
    _appKit?.onSessionUpdate.unsubscribe(_onSessionUpdate);

    await _connectionController.close();
    await _accountsChangedController.close();
  }
}
