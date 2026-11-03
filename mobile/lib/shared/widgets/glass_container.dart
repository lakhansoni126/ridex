import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum GlassVariant { card, panel, chip, intense, mapOverlay }

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.padding = const EdgeInsets.all(24.0),
    this.variant = GlassVariant.card,
    this.width,
    this.height,
    this.onTap,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final GlassVariant variant;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  double get _blur {
    switch (variant) {
      case GlassVariant.chip:
        return 8;
      case GlassVariant.mapOverlay:
        return 6;
      case GlassVariant.panel:
        return 14;
      case GlassVariant.intense:
        return 18;
      case GlassVariant.card:
        return 12;
    }
  }

  Color get _fill {
    switch (variant) {
      case GlassVariant.chip:
        return AppTheme.glass;
      case GlassVariant.mapOverlay:
        return const Color(0x990A0A0B);
      case GlassVariant.panel:
        return AppTheme.glass;
      case GlassVariant.intense:
        return AppTheme.glassIntense;
      case GlassVariant.card:
        return AppTheme.glass;
    }
  }

  Color get _border {
    switch (variant) {
      case GlassVariant.intense:
        return const Color(0x40FFFFFF);
      case GlassVariant.mapOverlay:
        return const Color(0x22FFFFFF);
      default:
        return AppTheme.glassBorder;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
        child: Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: _border, width: 1.2),
          ),
          child: child,
        ),
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: content,
      ),
    );
  }
}
