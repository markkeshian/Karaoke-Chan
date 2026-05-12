// lib/core/widgets/neon_card.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NeonCard extends StatelessWidget {
  const NeonCard({
    super.key,
    required this.child,
    this.gradient,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.glowColor,
  });

  final Widget child;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? glowColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          color: gradient == null ? AppTheme.surface : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (glowColor ?? AppTheme.primary).withOpacity(0.2),
            width: 1,
          ),
          boxShadow: glowColor != null
              ? [
                  BoxShadow(
                    color: glowColor!.withOpacity(0.15),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: padding != EdgeInsets.zero
              ? Padding(padding: padding, child: child)
              : child,
        ),
      ),
    );
  }
}
