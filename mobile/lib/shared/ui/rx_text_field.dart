import 'package:flutter/cupertino.dart';

import '../../core/theme/app_theme.dart';

/// Rounded filled text field (search-field look) for standalone inputs.
class RxTextField extends StatelessWidget {
  const RxTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.prefixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.textAlign = TextAlign.start,
    this.focusNode,
    this.suffix,
  });

  final TextEditingController controller;
  final String placeholder;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final TextAlign textAlign;
  final FocusNode? focusNode;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      placeholderStyle: rx.body.copyWith(color: rx.tertiaryLabel),
      style: style ?? rx.body,
      textAlign: textAlign,
      cursorColor: rx.accent,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      clearButtonMode: maxLines == 1
          ? OverlayVisibilityMode.editing
          : OverlayVisibilityMode.never,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      prefix: prefixIcon == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Icon(prefixIcon, size: 20, color: rx.secondaryLabel),
            ),
      suffix: suffix,
      decoration: BoxDecoration(
        color: rx.card,
        borderRadius: BorderRadius.circular(RxSpace.radius),
      ),
    );
  }
}

/// Labelled field row for use inside a `CupertinoFormSection`.
class RxFormField extends StatelessWidget {
  const RxFormField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.prefix,
    this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.suffix,
    this.autocorrect = true,
    this.maxLength,
  });

  final TextEditingController controller;
  final String placeholder;
  final String? prefix;
  final FormFieldValidator<String>? validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final int? maxLines;
  final Widget? suffix;
  final bool autocorrect;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final field = CupertinoTextFormFieldRow(
      controller: controller,
      placeholder: placeholder,
      placeholderStyle: rx.body.copyWith(color: rx.tertiaryLabel),
      style: rx.body,
      cursorColor: rx.accent,
      prefix: prefix == null
          ? null
          : SizedBox(
              width: 96,
              child: Text(prefix!, style: rx.body),
            ),
      validator: validator,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autofillHints: autofillHints,
      autocorrect: autocorrect && !obscureText,
      enableSuggestions: !obscureText,
      textCapitalization: textCapitalization,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
    );
    if (suffix == null) return field;
    return Row(children: [Expanded(child: field), suffix!]);
  }
}

/// Inset grouped form section matching [RxSection].
class RxFormSection extends StatelessWidget {
  const RxFormSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return CupertinoFormSection.insetGrouped(
      backgroundColor: rx.background,
      decoration: BoxDecoration(
        color: rx.card,
        borderRadius: BorderRadius.circular(RxSpace.radius),
      ),
      margin: const EdgeInsets.fromLTRB(RxSpace.inset, 0, RxSpace.inset, 8),
      header: header == null
          ? null
          : Text(header!.toUpperCase(), style: rx.footnote),
      footer: footer == null ? null : Text(footer!, style: rx.footnote),
      children: children,
    );
  }
}
