import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/wallet/wallet.dart';

/// Provider for DeepLinkService
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  return DeepLinkService.instance;
});

/// Provider for deep link stream
final deepLinkStreamProvider = StreamProvider<Uri>((ref) {
  final service = ref.watch(deepLinkServiceProvider);
  return service.deepLinkStream;
});

/// Provider for WalletService
final walletServiceProvider = Provider<WalletService>((ref) {
  final service = WalletService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for wallet connection status stream
final walletConnectionStreamProvider =
    StreamProvider<WalletConnectionStatus>((ref) {
  final service = ref.watch(walletServiceProvider);
  return service.connectionStream;
});

/// Provider for current connected wallet
final connectedWalletProvider = Provider<WalletEntity?>((ref) {
  final connectionStatus = ref.watch(walletConnectionStreamProvider);
  return connectionStatus.when(
    data: (status) => status.wallet,
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Provider for wallet connection state
final walletConnectionStateProvider = Provider<WalletConnectionState>((ref) {
  final connectionStatus = ref.watch(walletConnectionStreamProvider);
  return connectionStatus.when(
    data: (status) => status.state,
    loading: () => WalletConnectionState.disconnected,
    error: (_, __) => WalletConnectionState.error,
  );
});

/// Provider for checking if wallet is connected
final isWalletConnectedProvider = Provider<bool>((ref) {
  final state = ref.watch(walletConnectionStateProvider);
  return state == WalletConnectionState.connected;
});

/// Provider for retry status during connection
final walletRetryStatusProvider = Provider<WalletRetryStatus>((ref) {
  final connectionStatus = ref.watch(walletConnectionStreamProvider);
  return connectionStatus.when(
    data: (status) => WalletRetryStatus(
      isRetrying: status.isRetrying,
      currentAttempt: status.retryCount ?? 0,
      maxAttempts: status.maxRetries ?? 0,
      message: status.progressMessage,
    ),
    loading: () => const WalletRetryStatus(),
    error: (_, __) => const WalletRetryStatus(),
  );
});

/// Retry status model for UI
class WalletRetryStatus {
  final bool isRetrying;
  final int currentAttempt;
  final int maxAttempts;
  final String? message;

  const WalletRetryStatus({
    this.isRetrying = false,
    this.currentAttempt = 0,
    this.maxAttempts = 0,
    this.message,
  });

  String get displayMessage {
    if (isRetrying) {
      return message ?? 'Retrying connection ($currentAttempt/$maxAttempts)...';
    }
    return message ?? 'Connecting...';
  }
}

/// Notifier for wallet operations
class WalletNotifier extends StateNotifier<AsyncValue<WalletEntity?>> {
  final WalletService _walletService;
  StreamSubscription<Uri>? _deepLinkSubscription;

  WalletNotifier(this._walletService) : super(const AsyncValue.data(null)) {
    _init();
  }

  Future<void> _init() async {
    await _walletService.initialize();
    if (_walletService.connectedWallet != null) {
      state = AsyncValue.data(_walletService.connectedWallet);
    }

    // Register deep link handlers
    _setupDeepLinkHandlers();
  }

  void _setupDeepLinkHandlers() {
    final deepLinkService = DeepLinkService.instance;

    // Register handler for Phantom callbacks
    deepLinkService.registerHandler('phantom', (uri) async {
      await _walletService.handleDeepLink(uri);
    });

    // Register handler for MetaMask callbacks
    deepLinkService.registerHandler('metamask', (uri) async {
      await _walletService.handleDeepLink(uri);
    });

    // Register handler for WalletConnect callbacks
    deepLinkService.registerHandler('wc', (uri) async {
      await _walletService.handleDeepLink(uri);
    });

    // Subscribe to deep link stream for general handling
    _deepLinkSubscription = deepLinkService.deepLinkStream.listen((uri) {
      AppLogger.d('WalletNotifier received deep link: $uri');
    });
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  /// Connect to a wallet
  /// Uses stream as source of truth for final connection state
  Future<void> connect({
    required WalletType walletType,
    int? chainId,
    String? cluster,
  }) async {
    state = const AsyncValue.loading();

    // Use Completer to wait for final result from stream
    final completer = Completer<WalletEntity>();
    StreamSubscription<WalletConnectionStatus>? statusSubscription;

    statusSubscription = _walletService.connectionStream.listen((status) {
      AppLogger.wallet('Connection status update', data: {
        'state': status.state.name,
        'isRetrying': status.isRetrying,
        'retryCount': status.retryCount,
        'hasError': status.hasError,
      });

      if (status.isConnected && status.wallet != null) {
        // Final success - complete with wallet
        if (!completer.isCompleted) {
          AppLogger.wallet('Stream: Connection successful, completing');
          completer.complete(status.wallet);
        }
      } else if (status.hasError && !status.isRetrying) {
        // Final error (not during retry) - complete with error
        if (!completer.isCompleted) {
          AppLogger.wallet('Stream: Final error, completing with error');
          completer.completeError(
            WalletException(
              message: status.errorMessage ?? 'Connection failed',
              code: 'CONNECTION_ERROR',
            ),
          );
        }
      }
      // If isRetrying, we wait for the next status update
    });

    try {
      // Start connection - don't await the result directly
      // The stream will tell us the final outcome
      unawaited(
        _walletService.connect(
          walletType: walletType,
          chainId: chainId,
          cluster: cluster,
        ).then((_) {
          // Success handled by stream
        }).catchError((e) {
          // Log but don't propagate - stream is source of truth
          AppLogger.wallet('Connect method threw (stream is source of truth)', data: {
            'error': e.toString(),
          });
          return null;
        }),
      );

      // Wait for result from stream
      final wallet = await completer.future;
      state = AsyncValue.data(wallet);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    } finally {
      await statusSubscription.cancel();
    }
  }

  /// Disconnect from wallet
  Future<void> disconnect() async {
    try {
      await _walletService.disconnect();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Switch chain
  Future<void> switchChain(int chainId) async {
    try {
      await _walletService.switchChain(chainId);
      // Update state with new chain ID if needed
      if (state.value != null) {
        state = AsyncValue.data(state.value!.copyWith(chainId: chainId));
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Get connection URI
  Future<String?> getConnectionUri() async {
    return _walletService.getConnectionUri();
  }
}

/// Provider for wallet notifier
final walletNotifierProvider =
    StateNotifierProvider<WalletNotifier, AsyncValue<WalletEntity?>>((ref) {
  final service = ref.watch(walletServiceProvider);
  return WalletNotifier(service);
});

/// Provider for supported wallets
final supportedWalletsProvider = Provider<List<WalletInfo>>((ref) {
  return [
    WalletInfo(
      type: WalletType.metamask,
      name: 'MetaMask',
      description: 'Popular browser-based wallet',
      iconUrl: 'https://raw.githubusercontent.com/WalletConnect/walletconnect-assets/master/Icon/Gradient/Icon.png',
      supportsEvm: true,
      supportsSolana: false,
    ),
    WalletInfo(
      type: WalletType.walletConnect,
      name: 'WalletConnect',
      description: 'Connect any WalletConnect-compatible wallet',
      iconUrl: 'https://raw.githubusercontent.com/WalletConnect/walletconnect-assets/master/Icon/Gradient/Icon.png',
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.coinbase,
      name: 'Coinbase Wallet',
      description: 'Self-custody wallet by Coinbase',
      iconUrl: 'https://altcoinsbox.com/wp-content/uploads/2022/12/coinbase-logo.webp',
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.trustWallet,
      name: 'Trust Wallet',
      description: 'Multi-chain mobile wallet',
      iconUrl: 'https://trustwallet.com/assets/images/media/assets/TWT.png',
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.rainbow,
      name: 'Rainbow',
      description: 'Ethereum & Layer 2 wallet',
      iconUrl: 'https://avatars.githubusercontent.com/u/48327834?s=200&v=4',
      supportsEvm: true,
      supportsSolana: false,
    ),
    WalletInfo(
      type: WalletType.phantom,
      name: 'Phantom',
      description: 'Solana & Ethereum wallet',
      iconUrl: 'https://avatars.githubusercontent.com/u/78782331?s=200&v=4',
      supportsEvm: true,
      supportsSolana: true,
    ),
    WalletInfo(
      type: WalletType.rabby,
      name: 'Rabby',
      description: 'Multi-chain browser wallet',
      iconUrl: 'https://avatars.githubusercontent.com/u/81706530?s=200&v=4',
      supportsEvm: true,
      supportsSolana: false,
    ),
  ];
});

/// Wallet info model for display
class WalletInfo {
  final WalletType type;
  final String name;
  final String description;
  final String iconUrl;
  final bool supportsEvm;
  final bool supportsSolana;

  const WalletInfo({
    required this.type,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.supportsEvm,
    required this.supportsSolana,
  });
}
