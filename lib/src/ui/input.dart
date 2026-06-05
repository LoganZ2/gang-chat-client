import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'text_context_menu.dart';
import 'tokens.dart';

const double _inputHorizontalPadding = 12;
const double _inputVisualLift = 3;
const double _inputBaseDepth = 5;
const double _inputTextVerticalOffset = 4;
const double _inputIconVerticalOffset = 5;

class Input extends StatefulWidget {
  const Input({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'Message',
    this.enabled = true,
    this.obscureText = false,
    this.autofillHints,
    this.keyboardType,
    this.prefixIcon,
    this.suffix,
    this.minLines = 1,
    this.maxLines = 5,
    this.onSubmitted,
    this.onChanged,
    this.style = UiTypography.body,
    this.hintStyle = const TextStyle(color: UiColors.textMuted),
  });

  static const double defaultHeight = 40;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool enabled;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextStyle style;
  final TextStyle hintStyle;

  @override
  State<Input> createState() => _InputState();
}

class _InputState extends State<Input> {
  TextEditingController? _localController;
  FocusNode? _localFocusNode;
  bool _hovered = false;

  TextEditingController get _effectiveController =>
      widget.controller ?? _localController!;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _localFocusNode!;

  int get _effectiveMinLines => widget.obscureText ? 1 : widget.minLines;

  int get _effectiveMaxLines => widget.obscureText ? 1 : widget.maxLines;

  @override
  void initState() {
    super.initState();
    _localController = widget.controller == null
        ? TextEditingController()
        : null;
    _localFocusNode = widget.focusNode == null ? FocusNode() : null;
    _effectiveController.addListener(_handleTextChanged);
    _effectiveFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(Input oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController = oldWidget.controller ?? _localController;
    final needsLocalController =
        oldWidget.controller != null && widget.controller == null;
    final noLongerNeedsLocalController =
        oldWidget.controller == null && widget.controller != null;

    if (oldWidget.controller != widget.controller) {
      oldController?.removeListener(_handleTextChanged);
      if (needsLocalController) {
        _localController = TextEditingController();
      } else if (noLongerNeedsLocalController) {
        _localController?.dispose();
        _localController = null;
      }
      _effectiveController.addListener(_handleTextChanged);
    }

    final oldFocusNode = oldWidget.focusNode ?? _localFocusNode;
    final needsLocalFocusNode =
        oldWidget.focusNode != null && widget.focusNode == null;
    final noLongerNeedsLocalFocusNode =
        oldWidget.focusNode == null && widget.focusNode != null;

    if (oldWidget.focusNode != widget.focusNode) {
      oldFocusNode?.removeListener(_handleFocusChanged);
      if (needsLocalFocusNode) {
        _localFocusNode = FocusNode();
      } else if (noLongerNeedsLocalFocusNode) {
        _localFocusNode?.dispose();
        _localFocusNode = null;
      }
      _effectiveFocusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_handleTextChanged);
    _effectiveFocusNode.removeListener(_handleFocusChanged);
    _localController?.dispose();
    _localFocusNode?.dispose();
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  void _handleFocusChanged() => setState(() {});

  void _handleHoverChanged(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textMetrics = _textMetricsFor(
          context,
          maxWidth: constraints.maxWidth,
        );
        final focused = _effectiveFocusNode.hasFocus;

        final content = TextField(
          controller: _effectiveController,
          focusNode: _effectiveFocusNode,
          enabled: widget.enabled,
          obscureText: widget.obscureText,
          autofillHints: widget.autofillHints,
          keyboardType: widget.keyboardType,
          minLines: _effectiveMinLines,
          maxLines: _effectiveMaxLines,
          onSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          cursorColor: UiColors.accent,
          mouseCursor: widget.enabled
              ? SystemMouseCursors.text
              : SystemMouseCursors.basic,
          style: widget.style,
          textAlignVertical: TextAlignVertical.center,
          contextMenuBuilder: buildTextFieldContextMenu,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            hintStyle: widget.hintStyle,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: EdgeInsets.fromLTRB(
              _inputHorizontalPadding,
              textMetrics.topPadding,
              _inputHorizontalPadding,
              textMetrics.bottomPadding,
            ),
            prefixIcon: widget.prefixIcon == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(
                      left: _inputHorizontalPadding,
                      right: UiSpacing.sm,
                    ),
                    child: Transform.translate(
                      offset: const Offset(0, _inputIconVerticalOffset),
                      child: Icon(
                        widget.prefixIcon,
                        size: 17,
                        color: UiColors.textMuted,
                      ),
                    ),
                  ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            suffixIcon: widget.suffix == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(
                      left: UiSpacing.sm,
                      right: _inputHorizontalPadding,
                    ),
                    child: Transform.translate(
                      offset: const Offset(0, _inputIconVerticalOffset),
                      child: widget.suffix,
                    ),
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
          ),
        );

        final enabled = widget.enabled;
        final capTop = enabled && _hovered ? 0.0 : _inputVisualLift;
        final background = enabled
            ? focused
                  ? UiColors.selected
                  : UiColors.surface
            : UiColors.disabledSurface;
        final borderColor = enabled
            ? focused
                  ? UiColors.accentBorder
                  : UiColors.border
            : UiColors.disabledBorder;
        final shadowColor = Color.lerp(background, Colors.black, 0.46)!;

        return MouseRegion(
          cursor: enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
          onEnter: (_) => _handleHoverChanged(true),
          onExit: (_) => _handleHoverChanged(false),
          child: SizedBox(
            height: textMetrics.outerHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: _inputVisualLift + _inputBaseDepth,
                  height: textMetrics.height,
                  child: _InputLayer(
                    background: shadowColor,
                    borderColor: borderColor,
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 95),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: capTop,
                  height: textMetrics.height,
                  child: _InputLayer(
                    background: background,
                    borderColor: borderColor,
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _InputMetrics _textMetricsFor(
    BuildContext context, {
    required double maxWidth,
  }) {
    final text = _effectiveController.text;
    final measureText = text.isEmpty
        ? ' '
        : text.endsWith('\n')
        ? '$text '
        : text;
    final textWidth = math.max(0.0, maxWidth - (_inputHorizontalPadding * 2));
    final painter = TextPainter(
      text: TextSpan(text: measureText, style: widget.style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: _effectiveMaxLines,
    )..layout(maxWidth: textWidth);
    final lineCount = painter.computeLineMetrics().length.clamp(
      _effectiveMinLines,
      _effectiveMaxLines,
    );
    final lineHeight = painter.preferredLineHeight;
    final verticalPadding = math.max(
      0.0,
      (Input.defaultHeight - lineHeight) / 2,
    );
    final textOffset = math.min(_inputTextVerticalOffset, verticalPadding);
    final topPadding = verticalPadding + textOffset;
    final bottomPadding = verticalPadding - textOffset;
    final height = math.max(
      Input.defaultHeight,
      (lineHeight * lineCount) + topPadding + bottomPadding,
    );

    return _InputMetrics(
      height: height,
      outerHeight: height + _inputVisualLift + _inputBaseDepth,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
    );
  }
}

class _InputLayer extends StatelessWidget {
  const _InputLayer({
    required this.background,
    required this.borderColor,
    this.child,
  });

  final Color background;
  final Color borderColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(UiRadii.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(UiRadii.md),
          border: Border.all(color: borderColor),
        ),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

class _InputMetrics {
  const _InputMetrics({
    required this.height,
    required this.outerHeight,
    required this.topPadding,
    required this.bottomPadding,
  });

  final double height;
  final double outerHeight;
  final double topPadding;
  final double bottomPadding;
}
