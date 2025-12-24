import 'package:flutter/material.dart';

/// Reusable shimmer effect widget for loading placeholders.
///
/// Uses a LinearGradient animation that sweeps from left to right,
/// creating a shimmering loading effect.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
    this.child,
  });

  /// Width of the shimmer box. If null, fills available width.
  final double? width;

  /// Height of the shimmer box.
  final double? height;

  /// Border radius for rounded corners.
  final BorderRadius? borderRadius;

  /// Base color of the shimmer effect.
  final Color? baseColor;

  /// Highlight color that sweeps across.
  final Color? highlightColor;

  /// Optional child widget to apply shimmer effect to.
  final Widget? child;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.baseColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final highlightColor = widget.highlightColor ??
        theme.colorScheme.surface.withValues(alpha: 0.8);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Shimmer placeholder for text lines.
class ShimmerText extends StatelessWidget {
  const ShimmerText({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius,
  });

  /// Width of the text placeholder. If null, fills available width.
  final double? width;

  /// Height of the text line.
  final double height;

  /// Border radius for rounded corners.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: width,
      height: height,
      borderRadius: borderRadius ?? BorderRadius.circular(4),
    );
  }
}

/// Shimmer placeholder for circular avatars.
class ShimmerAvatar extends StatelessWidget {
  const ShimmerAvatar({
    super.key,
    this.size = 40,
  });

  /// Diameter of the avatar.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size / 2),
    );
  }
}

/// Shimmer placeholder for rectangular cards.
class ShimmerCard extends StatelessWidget {
  const ShimmerCard({
    super.key,
    this.width,
    this.height = 100,
    this.borderRadius,
  });

  /// Width of the card. If null, fills available width.
  final double? width;

  /// Height of the card.
  final double height;

  /// Border radius for rounded corners.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: width,
      height: height,
      borderRadius: borderRadius ?? BorderRadius.circular(16),
    );
  }
}

/// Shimmer placeholder for icon buttons or small squares.
class ShimmerIcon extends StatelessWidget {
  const ShimmerIcon({
    super.key,
    this.size = 24,
    this.borderRadius,
  });

  /// Size of the icon placeholder.
  final double size;

  /// Border radius. Defaults to slightly rounded corners.
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: size,
      height: size,
      borderRadius: borderRadius ?? BorderRadius.circular(6),
    );
  }
}

/// A row of shimmer placeholders with configurable spacing.
class ShimmerRow extends StatelessWidget {
  const ShimmerRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final double spacing;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }
}

/// A column of shimmer placeholders with configurable spacing.
class ShimmerColumn extends StatelessWidget {
  const ShimmerColumn({
    super.key,
    required this.children,
    this.spacing = 8,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final List<Widget> children;
  final double spacing;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i < children.length - 1) SizedBox(height: spacing),
        ],
      ],
    );
  }
}
