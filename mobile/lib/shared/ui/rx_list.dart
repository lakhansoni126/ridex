import 'package:flutter/cupertino.dart';

import '../../core/theme/app_theme.dart';

/// Inset-grouped section (the iOS Settings look).
class RxSection extends StatelessWidget {
  const RxSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.margin,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    if (children.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      backgroundColor: rx.background,
      decoration: BoxDecoration(
        color: rx.card,
        borderRadius: BorderRadius.circular(RxSpace.radius),
      ),
      separatorColor: rx.separator,
      margin: margin ??
          const EdgeInsetsDirectional.fromSTEB(
              RxSpace.inset, 0, RxSpace.inset, RxSpace.s),
      header: header == null
          ? null
          : Text(header!.toUpperCase(),
              style: rx.footnote.copyWith(letterSpacing: 0.2)),
      footer: footer == null ? null : Text(footer!, style: rx.footnote),
      children: children,
    );
  }
}

/// Settings-style row: coloured rounded-square icon, title, subtitle,
/// trailing detail and chevron.
class RxTile extends StatelessWidget {
  const RxTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leading,
    this.trailing,
    this.detail,
    this.onTap,
    this.chevron,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final Widget? trailing;
  final String? detail;
  final VoidCallback? onTap;

  /// Defaults to `onTap != null`.
  final bool? chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final lead = leading ??
        (icon == null
            ? null
            : RxIconBadge(icon: icon!, color: iconColor ?? rx.accent));
    final showChevron = chevron ?? onTap != null;

    return CupertinoListTile.notched(
      leading: lead,
      leadingSize: 30,
      title: Text(
        title,
        style: rx.body.copyWith(color: destructive ? rx.destructive : rx.label),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: rx.footnote, maxLines: 2),
      additionalInfo: detail == null
          ? null
          : Text(detail!, style: rx.body.copyWith(color: rx.secondaryLabel)),
      trailing: trailing ??
          (showChevron
              ? Icon(CupertinoIcons.chevron_right,
                  size: 16, color: rx.tertiaryLabel)
              : null),
      backgroundColor: rx.card,
      backgroundColorActivated: rx.fill,
      onTap: onTap,
    );
  }
}

/// 30pt rounded-square icon, as used in iOS Settings rows.
class RxIconBadge extends StatelessWidget {
  const RxIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.23),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.6, color: const Color(0xFFFFFFFF)),
    );
  }
}

/// Plain rounded card on the grouped background.
class RxCard extends StatelessWidget {
  const RxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(RxSpace.m),
    this.onTap,
    this.color,
    this.radius = RxSpace.radius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.rx.card,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return RxPressable(onTap: onTap!, child: card);
  }
}

/// Dims slightly while pressed (iOS highlight feedback) without ink splashes.
class RxPressable extends StatefulWidget {
  const RxPressable({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<RxPressable> createState() => _RxPressableState();
}

class _RxPressableState extends State<RxPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _down ? 0.6 : 1,
        child: widget.child,
      ),
    );
  }
}

/// Small rounded status pill ("LIVE", "Scheduled"...).
class RxPill extends StatelessWidget {
  const RxPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final fg = filled ? const Color(0xFFFFFFFF) : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withOpacity(rx.isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: rx.caption2.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Maps a group-ride status to a pill.
class RxRideStatusPill extends StatelessWidget {
  const RxRideStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return switch (status) {
      'live' => RxPill(
          label: 'LIVE',
          color: rx.destructive,
          icon: CupertinoIcons.circle_fill,
          filled: true),
      'scheduled' => RxPill(label: 'Scheduled', color: rx.info),
      'ended' => RxPill(label: 'Ended', color: rx.gray),
      'cancelled' => RxPill(label: 'Cancelled', color: rx.gray),
      _ => RxPill(label: status, color: rx.gray),
    };
  }
}
