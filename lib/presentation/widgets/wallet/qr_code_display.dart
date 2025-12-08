import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Widget for displaying WalletConnect QR code
class QrCodeDisplay extends StatelessWidget {
  final String uri;
  final double size;
  final VoidCallback? onCopy;

  const QrCodeDisplay({
    super.key,
    required this.uri,
    this.size = 220,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: QrImageView(
            data: uri,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Scan with your wallet app',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _copyUri(context),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy to clipboard'),
        ),
      ],
    );
  }

  void _copyUri(BuildContext context) {
    Clipboard.setData(ClipboardData(text: uri));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Connection URI copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    onCopy?.call();
  }
}

/// Modern bottom sheet modal for displaying QR code
class QrCodeModal extends StatelessWidget {
  final String uri;
  final String walletName;
  final VoidCallback? onCancel;

  const QrCodeModal({
    super.key,
    required this.uri,
    this.walletName = 'Wallet',
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.qr_code_scanner,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect $walletName',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scan QR code with your wallet app',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onCancel?.call();
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // QR Code section
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            child: Column(
              children: [
                // QR Code with animated border
                _AnimatedQrContainer(uri: uri),

                const SizedBox(height: 24),

                // Instructions
                _buildInstructions(theme),

                const SizedBox(height: 24),

                // Action buttons
                _buildActions(context, theme),
              ],
            ),
          ),

          // Safety info
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Only scan QR codes from trusted sources',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildInstructions(ThemeData theme) {
    return Column(
      children: [
        _InstructionStep(
          number: '1',
          text: 'Open your wallet app',
          theme: theme,
        ),
        const SizedBox(height: 12),
        _InstructionStep(
          number: '2',
          text: 'Tap the scan or connect button',
          theme: theme,
        ),
        const SizedBox(height: 12),
        _InstructionStep(
          number: '3',
          text: 'Scan this QR code',
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: uri));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Connection URI copied'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy Link'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onCancel?.call();
            },
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Cancel'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  /// Show QR code modal as a bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String uri,
    String walletName = 'Wallet',
    VoidCallback? onCancel,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QrCodeModal(
        uri: uri,
        walletName: walletName,
        onCancel: onCancel,
      ),
    );
  }
}

/// Animated container for QR code with glowing border
class _AnimatedQrContainer extends StatefulWidget {
  final String uri;

  const _AnimatedQrContainer({required this.uri});

  @override
  State<_AnimatedQrContainer> createState() => _AnimatedQrContainerState();
}

class _AnimatedQrContainerState extends State<_AnimatedQrContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: _animation.value * 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            width: 2,
          ),
        ),
        child: QrImageView(
          data: widget.uri,
          version: QrVersions.auto,
          size: 200,
          backgroundColor: Colors.white,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: theme.colorScheme.primary,
          ),
          dataModuleStyle: QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

/// Instruction step widget
class _InstructionStep extends StatelessWidget {
  final String number;
  final String text;
  final ThemeData theme;

  const _InstructionStep({
    required this.number,
    required this.text,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// Legacy dialog for backwards compatibility
class QrCodeDialog extends StatelessWidget {
  final String uri;
  final String title;

  const QrCodeDialog({
    super.key,
    required this.uri,
    this.title = 'Connect Wallet',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrCodeDisplay(uri: uri),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  /// Show QR code dialog
  static Future<void> show(
    BuildContext context, {
    required String uri,
    String title = 'Connect Wallet',
  }) {
    return showDialog(
      context: context,
      builder: (context) => QrCodeDialog(
        uri: uri,
        title: title,
      ),
    );
  }
}
