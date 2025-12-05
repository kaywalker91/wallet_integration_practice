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
    this.size = 250,
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
          onPressed: () {
            Clipboard.setData(ClipboardData(text: uri));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Connection URI copied to clipboard'),
                duration: Duration(seconds: 2),
              ),
            );
            onCopy?.call();
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy to clipboard'),
        ),
      ],
    );
  }
}

/// Dialog for displaying QR code
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
