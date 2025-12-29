import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';
import 'package:wallet_integration_practice/domain/entities/wallet_entity.dart';
import 'package:wallet_integration_practice/presentation/providers/wallet_provider.dart';
import 'package:wallet_integration_practice/presentation/screens/home/home_screen.dart';

class WalletConnectModal extends ConsumerStatefulWidget {
  const WalletConnectModal({
    super.key,
    this.walletType = WalletType.walletConnect,
  });

  final WalletType walletType;

  @override
  ConsumerState<WalletConnectModal> createState() => _WalletConnectModalState();
}

class _WalletConnectModalState extends ConsumerState<WalletConnectModal> {
  String? _uri;
  Timer? _poller;
  String? _errorMessage;
  bool _connectionSucceeded = false;
  
  // Safe reference to notifier for dispose logic
  // Storing this avoids "Bad state: Using ref when a widget is unmounted" error
  late final MultiWalletNotifier _walletNotifier;

  @override
  void initState() {
    super.initState();
    // Save reference safely in initState where ref is guaranteed to be valid
    _walletNotifier = ref.read(multiWalletNotifierProvider.notifier);
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialize();
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    
    // Only cancel pending connections if connection did NOT succeed
    // This prevents cleaning up a successfully connected wallet
    // Use Future to delay modification until after widget tree is done building
    if (!_connectionSucceeded) {
      final walletType = widget.walletType;
      final notifier = _walletNotifier;
      Future(() {
        notifier.cancelPendingConnections(walletType: walletType);
      });
    }
    
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      // Start connection
      // We don't await this directly because we want to poll for URI/Events
      // GenericWalletConnectAdapter logs to console but doesn't return until connected.
      // However, we need to catch errors.
      
      final connectFuture = ref.read(multiWalletNotifierProvider.notifier).connectWallet(
            walletType: widget.walletType,
          );
      
      // Handle the result of the connection specifically for errors or completion
      unawaited(connectFuture.then((_) {
        if (mounted) {
           _handleSuccess();
        }
      }).catchError((e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
          });
        }
      }));

      // Poll for URI
      _startUriPolling();

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _startUriPolling() {
    // Poll every 500ms for the URI
    _poller = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      // Check if we are already connected (provider update)
      final status = ref.read(walletConnectionStateProvider);
      if (status == WalletConnectionState.connected) {
         timer.cancel();
         _handleSuccess();
         return;
      }

      final uri = await ref.read(walletNotifierProvider.notifier).getConnectionUri();
      if (uri != null && uri != _uri) {
        setState(() {
          _uri = uri;
        });
      }
    });
  }
  
  void _handleSuccess() {
      // Mark connection as successful to prevent dispose from cancelling it
      _connectionSucceeded = true;
      
      // Navigate to Home or close
      // Since this is likely pushed on top of Home, we can pop or pushReplacement Home
      if (mounted) {
         Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
         );
      }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalletConnect'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_errorMessage != null)
                _buildErrorView(theme, _errorMessage!)
              else if (_uri != null)
                _buildQrView(theme, _uri!)
              else
                _buildLoadingView(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Integrating with WalletConnect...',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, String message) {
    return Column(
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(
          'Connection Failed',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            setState(() {
              _errorMessage = null;
            });
            _initialize();
          },
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildQrView(ThemeData theme, String uri) {
    return Column(
      children: [
        Text(
          'Scan with your wallet',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Scan this QR code with your mobile wallet to connect',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: QrImageView(
            data: uri,
            version: QrVersions.auto,
            size: 280,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: uri));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy Link'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () => _launchUri(uri),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open Wallet'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _launchUri(String uri) async {
    try {
      await launchUrl(
        Uri.parse(uri),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      AppLogger.e('Could not launch wallet URI', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open wallet app')),
        );
      }
    }
  }
}
