import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Dark gradient canvas + optional SafeArea / padding for glass screens.
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.padding,
    this.safeArea = true,
    this.extendBodyBehindAppBar = false,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final EdgeInsetsGeometry? padding;
  final bool safeArea;
  final bool extendBodyBehindAppBar;

  @override
  Widget build(BuildContext context) {
    Widget child = body;
    if (padding != null) {
      child = Padding(padding: padding!, child: child);
    }
    if (safeArea) {
      child = SafeArea(child: child);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: AppTheme.scaffoldGradient,
        child: child,
      ),
    );
  }
}
