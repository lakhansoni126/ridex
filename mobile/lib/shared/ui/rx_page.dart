import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/theme/app_theme.dart';

/// Top-level iOS page: large collapsing title, optional pull-to-refresh and
/// sliver content. Mirrors `NavigationStack` + `.navigationBarTitleDisplayMode(.large)`.
class RxLargeTitlePage extends StatelessWidget {
  const RxLargeTitlePage({
    super.key,
    required this.title,
    required this.slivers,
    this.trailing,
    this.leading,
    this.onRefresh,
    this.previousPageTitle,
    this.controller,
  });

  final String title;
  final List<Widget> slivers;
  final Widget? trailing;
  final Widget? leading;
  final Future<void> Function()? onRefresh;
  final String? previousPageTitle;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Material(
        type: MaterialType.transparency,
        child: CustomScrollView(
          controller: controller,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverNavigationBar(
              largeTitle: Text(title),
              leading: leading,
              previousPageTitle: previousPageTitle,
              trailing: trailing,
              backgroundColor: rx.bar,
              border: Border(
                bottom: BorderSide(color: rx.separator, width: 0.0),
              ),
              stretch: true,
            ),
            if (onRefresh != null)
              CupertinoSliverRefreshControl(onRefresh: onRefresh),
            ...slivers,
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + RxSpace.l,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pushed detail page with an inline (small) title.
class RxPage extends StatelessWidget {
  const RxPage({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.leading,
    this.previousPageTitle,
    this.backgroundColor,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? leading;
  final String? previousPageTitle;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return CupertinoPageScaffold(
      backgroundColor: backgroundColor ?? rx.background,
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        leading: leading,
        trailing: trailing,
        previousPageTitle: previousPageTitle,
        backgroundColor: rx.bar,
        border: Border(bottom: BorderSide(color: rx.separator, width: 0.0)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(bottom: false, child: child),
      ),
    );
  }
}

/// Text-only nav bar button (e.g. "Cancel", "Post").
class RxNavTextButton extends StatelessWidget {
  const RxNavTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.bold = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool bold;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: CupertinoActivityIndicator(),
      );
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: RxSpace.minTouch,
      onPressed: onPressed,
      child: Text(
        label,
        style: (bold ? rx.headline : rx.body).copyWith(
          color: onPressed == null ? rx.tertiaryLabel : rx.accent,
        ),
      ),
    );
  }
}

/// Icon nav bar button with a 44pt hit target.
class RxNavIconButton extends StatelessWidget {
  const RxNavIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minSize: RxSpace.minTouch,
        onPressed: onPressed,
        child: Icon(icon, size: 24, color: context.rx.accent),
      ),
    );
  }
}

/// Wraps a box widget as a sliver with standard horizontal insets.
class RxSliverPadding extends StatelessWidget {
  const RxSliverPadding({
    super.key,
    required this.child,
    this.top = 0,
    this.bottom = 0,
    this.horizontal = RxSpace.inset,
  });

  final Widget child;
  final double top;
  final double bottom;
  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom),
      sliver: SliverToBoxAdapter(child: child),
    );
  }
}
