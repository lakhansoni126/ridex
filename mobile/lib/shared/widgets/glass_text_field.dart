import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'glass_container.dart';

class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.onChanged,
    this.prefixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final IconData? prefixIcon;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      variant: GlassVariant.card,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        cursorColor: AppTheme.accent,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.textSecondary),
          prefixIcon: prefixIcon == null
              ? null
              : Icon(prefixIcon, color: AppTheme.textSecondary, size: 20),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// Multiple fields stacked inside one glass panel with dividers.
class GlassFormPanel extends StatelessWidget {
  const GlassFormPanel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(const Divider(color: Color(0x1FFFFFFF), height: 1));
      }
    }

    return GlassContainer(
      variant: GlassVariant.intense,
      borderRadius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(children: items),
    );
  }
}

class GlassFormField extends StatelessWidget {
  const GlassFormField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textPrimary),
      cursorColor: AppTheme.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textSecondary),
        border: InputBorder.none,
      ),
    );
  }
}
