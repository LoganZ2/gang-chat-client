import 'package:flutter/material.dart';

import 'tokens.dart';

class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? DefaultTextStyle.of(context).style;
    final spans = _highlightedSpans(
      text: text,
      query: query,
      style: effectiveStyle,
      highlightStyle: highlightStyle ?? _defaultHighlightStyle(effectiveStyle),
    );
    if (spans == null) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        softWrap: softWrap,
        style: effectiveStyle,
      );
    }

    return Text.rich(
      TextSpan(style: effectiveStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
    );
  }
}

TextStyle _defaultHighlightStyle(TextStyle baseStyle) {
  return baseStyle.copyWith(
    color: UiColors.accent,
    fontWeight: FontWeight.w700,
    backgroundColor: UiColors.accent.withValues(alpha: 0.2),
  );
}

List<TextSpan>? _highlightedSpans({
  required String text,
  required String query,
  required TextStyle style,
  required TextStyle highlightStyle,
}) {
  final needle = query.trim();
  if (text.isEmpty || needle.isEmpty) return null;

  final lowerText = text.toLowerCase();
  final lowerNeedle = needle.toLowerCase();
  var searchStart = 0;
  var hasMatch = false;
  final spans = <TextSpan>[];

  while (searchStart < text.length) {
    final matchStart = lowerText.indexOf(lowerNeedle, searchStart);
    if (matchStart < 0) break;
    final matchEnd = matchStart + needle.length;
    if (matchStart > searchStart) {
      spans.add(TextSpan(text: text.substring(searchStart, matchStart)));
    }
    spans.add(
      TextSpan(
        text: text.substring(matchStart, matchEnd),
        style: highlightStyle,
      ),
    );
    hasMatch = true;
    searchStart = matchEnd;
  }

  if (!hasMatch) return null;
  if (searchStart < text.length) {
    spans.add(TextSpan(text: text.substring(searchStart)));
  }
  return spans;
}
