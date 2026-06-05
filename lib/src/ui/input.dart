import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'button.dart';
import 'text_context_menu.dart';
import 'tokens.dart';

const double _inputHorizontalPadding = 12;
const double _inputVisualLift = 3;

class Input extends StatefulWidget {
  const Input({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = 'Message',
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

  TextEditingController get _effectiveController =>
      widget.controller ?? _localController!;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _localFocusNode!;

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textMetrics = _textMetricsFor(
          context,
          maxWidth: constraints.maxWidth,
        );
        final focused = _effectiveFocusNode.hasFocus;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _effectiveFocusNode.requestFocus(),
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: PressableSurface(
              height: textMetrics.height,
              interactive: true,
              mouseCursor: SystemMouseCursors.text,
              hoverEffect: true,
              pressEffect: false,
              borderRadius: UiRadii.md,
              backgroundColor: UiColors.surface,
              borderColor: focused ? UiColors.accentBorder : UiColors.border,
              padding: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _inputHorizontalPadding,
                  textMetrics.topPadding,
                  _inputHorizontalPadding,
                  textMetrics.bottomPadding,
                ),
                child: TextField(
                  controller: _effectiveController,
                  focusNode: _effectiveFocusNode,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  onSubmitted: widget.onSubmitted,
                  onChanged: widget.onChanged,
                  cursorColor: UiColors.accent,
                  mouseCursor: SystemMouseCursors.text,
                  style: widget.style,
                  textAlignVertical: TextAlignVertical.center,
                  contextMenuBuilder: buildTextFieldContextMenu,
                  decoration: InputDecoration.collapsed(
                    hintText: widget.hintText,
                    hintStyle: widget.hintStyle,
                  ),
                ),
              ),
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
      maxLines: widget.maxLines,
    )..layout(maxWidth: textWidth);
    final lineCount = painter.computeLineMetrics().length.clamp(
      widget.minLines,
      widget.maxLines,
    );
    final lineHeight = painter.preferredLineHeight;
    final verticalPadding = math.max(
      0.0,
      (Input.defaultHeight - lineHeight) / 2,
    );
    final topPadding = math.max(0.0, verticalPadding - _inputVisualLift);
    final bottomPadding = (verticalPadding * 2) - topPadding;
    final height = math.max(
      Input.defaultHeight,
      (lineHeight * lineCount) + topPadding + bottomPadding,
    );

    return _InputMetrics(
      height: height,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
    );
  }
}

class _InputMetrics {
  const _InputMetrics({
    required this.height,
    required this.topPadding,
    required this.bottomPadding,
  });

  final double height;
  final double topPadding;
  final double bottomPadding;
}
