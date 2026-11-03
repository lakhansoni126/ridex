import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'glass_container.dart';

enum GlassButtonStyle { primary, secondary }

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = GlassButtonStyle.primary,
    this.busy = false,
    this.expanded = true,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final GlassButtonStyle style;
  final bool busy;
  final bool expanded;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final child = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.textPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: AppTheme.textPrimary),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppTheme.textPrimary,
                    ),
              ),
            ],
          );

    if (style == GlassButtonStyle.primary) {
      final button = ElevatedButton(
        onPressed: enabled ? onPressed : null,
        child: child,
      );
      return expanded
          ? SizedBox(width: double.infinity, height: 56, child: button)
          : SizedBox(height: 48, child: button);
    }

    final glass = GlassContainer(
      variant: GlassVariant.chip,
      borderRadius: 16,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: expanded ? 56 : 48,
            width: expanded ? double.infinity : null,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Opacity(opacity: enabled ? 1 : 0.45, child: child),
          ),
        ),
      ),
    );

    return glass;
  }
}
