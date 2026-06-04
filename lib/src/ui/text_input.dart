import 'package:flutter/material.dart';

import 'tokens.dart';

class TextInput extends StatelessWidget {
  const TextInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final field = DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.lg),
        border: Border.all(color: UiColors.border),
      ),
      child: Row(
        crossAxisAlignment: maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (prefixIcon != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 12),
              child: Icon(prefixIcon, size: 18, color: UiColors.textMuted),
            ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              minLines: minLines,
              maxLines: maxLines,
              onSubmitted: onSubmitted,
              cursorColor: UiColors.accent,
              style: UiTypography.body,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                hintStyle: const TextStyle(color: UiColors.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
            ),
          ),
          if (suffix != null)
            Padding(padding: const EdgeInsets.only(right: 6), child: suffix),
        ],
      ),
    );

    if (label == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label!, style: UiTypography.label),
        const SizedBox(height: 7),
        field,
      ],
    );
  }
}
