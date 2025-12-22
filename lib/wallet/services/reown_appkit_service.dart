import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';

/// Provider for ReownAppKitService
final reownAppKitServiceProvider = Provider<ReownAppKitService>((ref) {
  return ReownAppKitService();
});

/// Connection status for AppKit
enum AppKitConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// AppKit connection status with wallet info
class AppKitConnectionStatus {
  final AppKitConnectionState state;
  final WalletEntity? wallet;
  final String? errorMessage;

  const AppKitConnectionStatus._({
    required this.state,
    this.wallet,
    this.errorMessage,
  });

  factory AppKitConnectionStatus.disconnected() =>
      const AppKitConnectionStatus._(state: AppKitConnectionState.disconnected);

  factory AppKitConnectionStatus.connecting() =>
      const AppKitConnectionStatus._(state: AppKitConnectionState.connecting);

  factory AppKitConnectionStatus.connected(WalletEntity wallet) =>
      AppKitConnectionStatus._(
        state: AppKitConnectionState.connected,
        wallet: wallet,
      );

  factory AppKitConnectionStatus.error(String message) =>
      AppKitConnectionStatus._(
        state: AppKitConnectionState.error,
        errorMessage: message,
      );

  bool get isConnected => state == AppKitConnectionState.connected;
  bool get isConnecting => state == AppKitConnectionState.connecting;
  bool get isDisconnected => state == AppKitConnectionState.disconnected;
  bool get hasError => state == AppKitConnectionState.error;
}

/// Reown AppKit Service - Handles wallet connections via AppKit modal
///
/// This service wraps the Reown AppKit (formerly Web3Modal) to provide
/// a unified wallet connection experience with automatic deep link handling,
/// relay connection management, and session persistence.
class ReownAppKitService {
  ReownAppKitModal? _appKitModal;
  bool _isInitialized = false;

  final _connectionController =
      StreamController<AppKitConnectionStatus>.broadcast();

  ReownAppKitModal? get appKitModal => _appKitModal;
  bool get isInitialized => _isInitialized;

  /// Stream of connection status updates
  Stream<AppKitConnectionStatus> get connectionStream =>
      _connectionController.stream;

  /// Current connection status
  AppKitConnectionStatus get currentStatus {
    if (!_isInitialized || _appKitModal == null) {
      return AppKitConnectionStatus.disconnected();
    }

    if (_appKitModal!.isConnected) {
      final wallet = _createWalletEntity();
      if (wallet != null) {
        return AppKitConnectionStatus.connected(wallet);
      }
    }

    return AppKitConnectionStatus.disconnected();
  }

  /// Initialize AppKit with context
  ///
  /// Must be called before any other operations.
  /// Typically called in the app's MaterialApp builder.
  Future<void> initialize(BuildContext context) async {
    if (_isInitialized && _appKitModal != null) {
      AppLogger.i('ReownAppKitService already initialized');
      return;
    }

    try {
      final pairingMetadata = PairingMetadata(
        name: AppConstants.appName,
        description: AppConstants.appDescription,
        url: AppConstants.appUrl,
        icons: [AppConstants.appIcon],
        redirect: Redirect(
          native: '${AppConstants.deepLinkScheme}://',
          universal: 'https://${AppConstants.universalLinkHost}/app',
        ),
      );

      _appKitModal = ReownAppKitModal(
        context: context,
        projectId: AppConstants.walletConnectProjectId,
        metadata: pairingMetadata,
        featuresConfig: FeaturesConfig(
          email: false,
          socials: [],
          showMainWallets: true,
        ),
        // Limit wallets to supported ones to prevent checking all installed apps (scans 100+ apps)
        // This resolves the UI freeze/skip frames issue caused by Excessive getAppPackageInfo
        includedWalletIds: {
          'c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96', // MetaMask
          'fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa', // Coinbase Wallet
          '4622a2b2d6af1c9844944291e5e7351a6aa24cd7b23099efac1b2fd875da31a0', // Trust Wallet
          'a797aa35c0fadbfc1a53e7f675162ed522696a254325dbef622445543a8e7e31', // Phantom
          'ac78170cfa5f83da4bf6d9124237d1d23b6b63778505500806443c528f804568', // Rabby
        },
        // Supported networks - uses default eip155 chains
        optionalNamespaces: {
          'eip155': RequiredNamespace(
            chains: [
              'eip155:1',    // Ethereum
              'eip155:137',  // Polygon
              'eip155:42161', // Arbitrum
              'eip155:10',   // Optimism
              'eip155:8453', // Base
              'eip155:56',   // BNB Smart Chain
            ],
            methods: [
              'eth_sendTransaction',
              'eth_signTransaction',
              'eth_sign',
              'personal_sign',
              'eth_signTypedData',
              'eth_signTypedData_v3',
              'eth_signTypedData_v4',
              'wallet_switchEthereumChain',
              'wallet_addEthereumChain',
            ],
            events: [
              'chainChanged',
              'accountsChanged',
              'message',
              'disconnect',
              'connect',
            ],
          ),
        },
      );

      await _appKitModal!.init();

      // Setup event listeners
      _setupEventListeners();

      _isInitialized = true;
      AppLogger.i('ReownAppKitModal initialized successfully');

      // Check if already connected (session restore)
      if (_appKitModal!.isConnected) {
        final wallet = _createWalletEntity();
        if (wallet != null) {
          _connectionController.add(AppKitConnectionStatus.connected(wallet));
          AppLogger.wallet('AppKit session restored', data: {
            'address': wallet.address,
            'chainId': wallet.chainId,
          });
        }
      }
    } catch (e) {
      AppLogger.e('Failed to initialize ReownAppKitModal', e);
      _isInitialized = false;
      _connectionController.add(
        AppKitConnectionStatus.error('Initialization failed: $e'),
      );
    }
  }

  /// Setup event listeners for AppKit modal
  void _setupEventListeners() {
    if (_appKitModal == null) return;

    // Listen to modal state changes
    _appKitModal!.onModalConnect.subscribe((event) {
      AppLogger.wallet('AppKit onModalConnect', data: {
        'session': event?.session?.topic,
      });
      _handleConnectionChange();
    });

    _appKitModal!.onModalDisconnect.subscribe((event) {
      AppLogger.wallet('AppKit onModalDisconnect');
      _connectionController.add(AppKitConnectionStatus.disconnected());
    });

    _appKitModal!.onModalError.subscribe((event) {
      AppLogger.e('AppKit onModalError', event?.message);
      _connectionController.add(
        AppKitConnectionStatus.error(event?.message ?? 'Unknown error'),
      );
    });

    _appKitModal!.onModalNetworkChange.subscribe((event) {
      AppLogger.wallet('AppKit network changed', data: {
        'chainId': event?.chainId,
      });
      _handleConnectionChange();
    });

    // Session events
    _appKitModal!.onSessionEventEvent.subscribe((event) {
      AppLogger.wallet('AppKit session event', data: {
        'name': event?.name,
        'data': event?.data?.toString(),
      });
    });

    _appKitModal!.onSessionUpdateEvent.subscribe((event) {
      AppLogger.wallet('AppKit session update');
      _handleConnectionChange();
    });
  }

  /// Handle connection state changes
  void _handleConnectionChange() {
    if (_appKitModal == null || !_isInitialized) return;

    if (_appKitModal!.isConnected) {
      final wallet = _createWalletEntity();
      if (wallet != null) {
        _connectionController.add(AppKitConnectionStatus.connected(wallet));
      }
    } else {
      _connectionController.add(AppKitConnectionStatus.disconnected());
    }
  }

  /// Create WalletEntity from current AppKit session
  WalletEntity? _createWalletEntity() {
    if (_appKitModal == null || !_appKitModal!.isConnected) return null;

    final session = _appKitModal!.session;
    if (session == null) return null;

    // Get address using the getAddress method with eip155 namespace
    final sessionAddress = session.getAddress('eip155');
    if (sessionAddress == null || sessionAddress.isEmpty) return null;

    // Get chain ID from selected chain
    int? currentChainId;
    final selectedChain = _appKitModal!.selectedChain;
    if (selectedChain != null) {
      currentChainId = int.tryParse(selectedChain.chainId);
    }

    // Determine wallet type from session metadata
    final walletType = _determineWalletType(session);

    return WalletEntity(
      address: sessionAddress,
      type: walletType,
      chainId: currentChainId ?? 1, // Default to Ethereum mainnet
      connectedAt: DateTime.now(),
    );
  }

  /// Determine wallet type from session metadata
  WalletType _determineWalletType(ReownAppKitModalSession session) {
    final peerName = session.peer?.metadata.name.toLowerCase() ?? '';

    if (peerName.contains('coinbase')) return WalletType.coinbase;
    if (peerName.contains('metamask')) return WalletType.metamask;
    if (peerName.contains('trust')) return WalletType.trustWallet;
    if (peerName.contains('phantom')) return WalletType.phantom;
    if (peerName.contains('rabby')) return WalletType.rabby;

    // Default to WalletConnect for unknown wallets
    return WalletType.walletConnect;
  }

  /// Open AppKit modal for wallet connection
  ///
  /// This opens the Reown AppKit modal which handles:
  /// - Wallet selection (QR code, deep links, browser wallets)
  /// - Session management
  /// - Deep link handling for mobile wallets
  Future<void> openModal() async {
    if (!_isInitialized || _appKitModal == null) {
      AppLogger.w('ReownAppKitModal not initialized');
      throw const WalletException(
        message: 'AppKit not initialized. Please try again.',
        code: 'NOT_INITIALIZED',
      );
    }

    _connectionController.add(AppKitConnectionStatus.connecting());

    try {
      await _appKitModal!.openModalView();
    } catch (e) {
      AppLogger.e('Failed to open AppKit modal', e);
      _connectionController.add(
        AppKitConnectionStatus.error('Failed to open wallet selector'),
      );
      rethrow;
    }
  }

  /// Disconnect from current wallet
  Future<void> disconnect() async {
    if (!_isInitialized || _appKitModal == null) return;

    try {
      await _appKitModal!.disconnect();
      _connectionController.add(AppKitConnectionStatus.disconnected());
      AppLogger.wallet('AppKit disconnected');
    } catch (e) {
      AppLogger.e('Failed to disconnect AppKit', e);
      // Still emit disconnected status
      _connectionController.add(AppKitConnectionStatus.disconnected());
    }
  }

  /// Check if currently connected
  bool get isConnected => _appKitModal?.isConnected ?? false;

  /// Get current connected address
  String? get address => _appKitModal?.session?.getAddress('eip155');

  /// Get current chain ID
  int? get chainId {
    final chain = _appKitModal?.selectedChain;
    if (chain != null) {
      return int.tryParse(chain.chainId);
    }
    return null;
  }

  /// Get current session
  ReownAppKitModalSession? get session => _appKitModal?.session;

  /// Switch to a different chain
  Future<void> switchChain(int targetChainId) async {
    if (!_isInitialized || _appKitModal == null) {
      throw const WalletException(
        message: 'AppKit not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    if (!isConnected) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final chainIdStr = targetChainId.toString();
      final targetNetwork = ReownAppKitModalNetworks.getNetworkInfo(
        'eip155',
        chainIdStr,
      );

      if (targetNetwork == null) {
        throw WalletException(
          message: 'Unsupported chain: $targetChainId',
          code: 'UNSUPPORTED_CHAIN',
        );
      }

      await _appKitModal!.selectChain(targetNetwork);
      AppLogger.wallet('AppKit chain switched', data: {'chainId': targetChainId});
    } catch (e) {
      AppLogger.e('Failed to switch chain', e);
      rethrow;
    }
  }

  /// Send a personal sign request
  Future<String> personalSign(String message, String signerAddress) async {
    if (!_isInitialized || _appKitModal == null) {
      throw const WalletException(
        message: 'AppKit not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    if (!isConnected) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final result = await _appKitModal!.request(
        topic: session!.topic!,
        chainId: 'eip155:${chainId ?? 1}',
        request: SessionRequestParams(
          method: 'personal_sign',
          params: [message, signerAddress],
        ),
      );

      AppLogger.wallet('Personal sign completed');
      return result as String;
    } catch (e) {
      AppLogger.e('Personal sign failed', e);
      throw WalletException(
        message: 'Signing failed: $e',
        code: 'SIGN_ERROR',
        originalException: e,
      );
    }
  }

  /// Send a transaction
  Future<String> sendTransaction({
    required String to,
    required String value,
    String? data,
    String? from,
  }) async {
    if (!_isInitialized || _appKitModal == null) {
      throw const WalletException(
        message: 'AppKit not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    if (!isConnected) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final txParams = {
        'from': from ?? address,
        'to': to,
        'value': value,
        if (data != null) 'data': data,
      };

      final result = await _appKitModal!.request(
        topic: session!.topic!,
        chainId: 'eip155:${chainId ?? 1}',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [txParams],
        ),
      );

      AppLogger.wallet('Transaction sent', data: {'hash': result});
      return result as String;
    } catch (e) {
      AppLogger.e('Transaction failed', e);
      throw WalletException(
        message: 'Transaction failed: $e',
        code: 'TX_ERROR',
        originalException: e,
      );
    }
  }

  /// Sign typed data (EIP-712)
  Future<String> signTypedData(String signerAddress, String typedData) async {
    if (!_isInitialized || _appKitModal == null) {
      throw const WalletException(
        message: 'AppKit not initialized',
        code: 'NOT_INITIALIZED',
      );
    }

    if (!isConnected) {
      throw const WalletException(
        message: 'No wallet connected',
        code: 'NOT_CONNECTED',
      );
    }

    try {
      final result = await _appKitModal!.request(
        topic: session!.topic!,
        chainId: 'eip155:${chainId ?? 1}',
        request: SessionRequestParams(
          method: 'eth_signTypedData_v4',
          params: [signerAddress, typedData],
        ),
      );

      AppLogger.wallet('Typed data signed');
      return result as String;
    } catch (e) {
      AppLogger.e('Typed data signing failed', e);
      throw WalletException(
        message: 'Signing failed: $e',
        code: 'SIGN_ERROR',
        originalException: e,
      );
    }
  }

  /// Get the AppKit connect button widget
  ///
  /// Returns a pre-built button that opens the AppKit modal.
  /// Use this for quick integration without custom UI.
  Widget? getConnectButton({
    BaseButtonSize size = BaseButtonSize.regular,
  }) {
    if (!_isInitialized || _appKitModal == null) return null;

    return AppKitModalConnectButton(
      appKit: _appKitModal!,
      size: size,
    );
  }

  /// Get the network selection button widget
  Widget? getNetworkButton({
    BaseButtonSize size = BaseButtonSize.regular,
  }) {
    if (!_isInitialized || _appKitModal == null) return null;

    return AppKitModalNetworkSelectButton(
      appKit: _appKitModal!,
      size: size,
    );
  }

  /// Get the account button widget (shows connected address)
  Widget? getAccountButton({
    BaseButtonSize size = BaseButtonSize.regular,
  }) {
    if (!_isInitialized || _appKitModal == null) return null;

    return AppKitModalAccountButton(
      appKitModal: _appKitModal!,
      size: size,
    );
  }

  /// Dispose resources
  void dispose() {
    _connectionController.close();
    // AppKit modal doesn't have a dispose method
  }
}
