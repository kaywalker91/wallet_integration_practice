import 'package:flutter/material.dart';

/// Loading overlay widget
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
    this.backgroundColor,
  });

  final bool isLoading;
  final Widget child;
  final String? message;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          ColoredBox(
            color: backgroundColor ?? Colors.black.withValues(alpha: 0.5),
            child: Center(
              child: Card(
                margin: const EdgeInsets.all(32),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      if (message != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Simple loading indicator
class LoadingIndicator extends StatelessWidget {
  const LoadingIndicator({
    super.key,
    this.message,
    this.size = 24,
  });

  final String? message;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
