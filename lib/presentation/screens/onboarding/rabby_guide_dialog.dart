import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wallet_integration_practice/core/core.dart';

/// Rabby 내장 브라우저 사용 안내 다이얼로그
///
/// Rabby 모바일 앱은 WalletConnect Deep Link를 지원하지 않으므로,
/// 사용자에게 내장 브라우저를 통한 연결 방법을 안내합니다.
class RabbyGuideDialog extends StatefulWidget {
  const RabbyGuideDialog({
    super.key,
    this.onCancel,
  });

  final VoidCallback? onCancel;

  @override
  State<RabbyGuideDialog> createState() => _RabbyGuideDialogState();
}

class _RabbyGuideDialogState extends State<RabbyGuideDialog> {
  bool _urlCopied = false;

  Future<void> _copyDappUrl() async {
    await Clipboard.setData(
      const ClipboardData(text: AppConstants.dappUrl),
    );
    setState(() => _urlCopied = true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('URL이 복사되었습니다'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Reset after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _urlCopied = false);
      }
    });
  }

  Future<void> _openRabbyApp() async {
    try {
      final uri = Uri.parse(WalletConstants.rabbyDeepLink);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.e('Error opening Rabby app', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Rabby 앱을 열 수 없습니다'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const rabbyColor = Color(0xFF8697FF);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rabby Icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: rabbyColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.pets,
                size: 36,
                color: rabbyColor,
              ),
            ),

            const SizedBox(height: 20),

            // Title
            Text(
              'Rabby로 연결하기',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            // Description
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rabby 앱은 내장 브라우저를 통해 연결합니다.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStep(theme, 1, 'URL을 복사하세요'),
                  const SizedBox(height: 8),
                  _buildStep(theme, 2, 'Rabby 앱 → Dapps 탭'),
                  const SizedBox(height: 8),
                  _buildStep(theme, 3, 'URL 붙여넣기 → 연결'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // URL Copy Section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _urlCopied ? Colors.green : theme.colorScheme.outline,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppConstants.dappUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _copyDappUrl,
                    icon: Icon(
                      _urlCopied ? Icons.check : Icons.copy,
                      size: 20,
                      color: _urlCopied ? Colors.green : rabbyColor,
                    ),
                    tooltip: 'URL 복사',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                // Cancel Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onCancel?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('취소'),
                  ),
                ),

                const SizedBox(width: 12),

                // Open Rabby Button
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _openRabbyApp,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Rabby 열기'),
                    style: FilledButton.styleFrom(
                      backgroundColor: rabbyColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(ThemeData theme, int number, String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$number',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
