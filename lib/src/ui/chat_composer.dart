import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'button.dart';
import 'tokens.dart';

const double _composerControlHeight = 40;
const double _composerControlOuterHeight = _composerControlHeight + 8;
const double _composerTextHorizontalPadding = 12;
const double _composerTextVisualLift = 3;

enum ComposerPanelType { list, static }

class ComposerAction {
  const ComposerAction({
    required this.id,
    required this.icon,
    required this.label,
    this.tooltip,
    this.panel,
    this.onPressed,
    this.tone = ButtonTone.neutral,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? tooltip;
  final ComposerPanel? panel;
  final VoidCallback? onPressed;
  final ButtonTone tone;

  bool get opensPanel => panel != null;
}

class ComposerPanel {
  const ComposerPanel.list({
    required this.itemCount,
    required this.itemBuilder,
    this.height = 220,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 14),
  }) : type = ComposerPanelType.list,
       child = null;

  const ComposerPanel.static({
    required this.child,
    this.height = 124,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 14),
  }) : type = ComposerPanelType.static,
       itemCount = 0,
       itemBuilder = null;

  final ComposerPanelType type;
  final int itemCount;
  final IndexedWidgetBuilder? itemBuilder;
  final Widget? child;
  final double height;
  final EdgeInsetsGeometry padding;
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.actions,
    this.controller,
    this.hintText = 'Message',
    this.minLines = 1,
    this.maxLines = 5,
    this.onSubmitted,
    this.onChanged,
  });

  final List<ComposerAction> actions;
  final TextEditingController? controller;
  final String hintText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final FocusNode _inputFocusNode = FocusNode();
  String? _openActionId;

  ComposerAction? get _openAction {
    final id = _openActionId;
    if (id == null) return null;
    for (final action in widget.actions) {
      if (action.id == id && action.panel != null) return action;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _inputFocusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _inputFocusNode.removeListener(_handleFocusChanged);
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() => setState(() {});

  void _handleAction(ComposerAction action) {
    if (action.panel == null) {
      if (_openActionId != null) setState(() => _openActionId = null);
      action.onPressed?.call();
      return;
    }

    setState(() {
      _openActionId = _openActionId == action.id ? null : action.id;
    });
    action.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final openAction = _openAction;
    final openPanel = openAction?.panel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final composer = DecoratedBox(
          decoration: BoxDecoration(
            color: UiColors.surfaceLow,
            borderRadius: BorderRadius.circular(UiRadii.lg),
            border: Border.all(color: UiColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(UiRadii.lg),
            child: _ComposerContent(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: openPanel == null
                        ? const SizedBox(width: double.infinity)
                        : _ComposerPanelFrame(
                            key: ValueKey(openAction!.id),
                            panel: openPanel,
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _ComposerTextBox(
                            controller: widget.controller,
                            focusNode: _inputFocusNode,
                            hintText: widget.hintText,
                            minLines: widget.minLines,
                            maxLines: widget.maxLines,
                            onSubmitted: widget.onSubmitted,
                            onChanged: widget.onChanged,
                          ),
                        ),
                        if (widget.actions.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          _ComposerActionRow(
                            actions: widget.actions,
                            openActionId: _openActionId,
                            onAction: _handleAction,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (!constraints.hasBoundedWidth) return composer;
        return SizedBox(width: constraints.maxWidth, child: composer);
      },
    );
  }
}

class _ComposerActionRow extends StatelessWidget {
  const _ComposerActionRow({
    required this.actions,
    required this.openActionId,
    required this.onAction,
  });

  final List<ComposerAction> actions;
  final String? openActionId;
  final ValueChanged<ComposerAction> onAction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _composerControlOuterHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            ButtonIcon(
              tooltip: actions[index].tooltip ?? actions[index].label,
              icon: Icon(actions[index].icon),
              tone: actions[index].tone,
              selected: actions[index].id == openActionId,
              onPressed: () => onAction(actions[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComposerTextBox extends StatefulWidget {
  const _ComposerTextBox({
    required this.hintText,
    required this.minLines,
    required this.maxLines,
    this.controller,
    this.focusNode,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<_ComposerTextBox> createState() => _ComposerTextBoxState();
}

class _ComposerTextBoxState extends State<_ComposerTextBox> {
  TextEditingController? _localController;

  TextEditingController get _effectiveController =>
      widget.controller ?? _localController!;

  @override
  void initState() {
    super.initState();
    _localController = widget.controller == null
        ? TextEditingController()
        : null;
    _effectiveController.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(_ComposerTextBox oldWidget) {
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
  }

  @override
  void dispose() {
    _effectiveController.removeListener(_handleTextChanged);
    _localController?.dispose();
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textMetrics = _textMetricsFor(
          context,
          maxWidth: constraints.maxWidth,
        );
        final focused = widget.focusNode?.hasFocus ?? false;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => widget.focusNode?.requestFocus(),
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
                  _composerTextHorizontalPadding,
                  textMetrics.topPadding,
                  _composerTextHorizontalPadding,
                  textMetrics.bottomPadding,
                ),
                child: TextField(
                  controller: _effectiveController,
                  focusNode: widget.focusNode,
                  minLines: widget.minLines,
                  maxLines: widget.maxLines,
                  onSubmitted: widget.onSubmitted,
                  onChanged: widget.onChanged,
                  cursorColor: UiColors.accent,
                  mouseCursor: SystemMouseCursors.text,
                  style: UiTypography.body,
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration.collapsed(
                    hintText: widget.hintText,
                    hintStyle: const TextStyle(color: UiColors.textMuted),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  _ComposerTextMetrics _textMetricsFor(
    BuildContext context, {
    required double maxWidth,
  }) {
    final text = _effectiveController.text;
    final measureText = text.isEmpty
        ? ' '
        : text.endsWith('\n')
        ? '$text '
        : text;
    final textWidth = math.max(
      0.0,
      maxWidth - (_composerTextHorizontalPadding * 2),
    );
    final painter = TextPainter(
      text: TextSpan(text: measureText, style: UiTypography.body),
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
      (_composerControlHeight - lineHeight) / 2,
    );
    final topPadding = math.max(0.0, verticalPadding - _composerTextVisualLift);
    final bottomPadding = (verticalPadding * 2) - topPadding;
    final height = math.max(
      _composerControlHeight,
      (lineHeight * lineCount) + topPadding + bottomPadding,
    );

    return _ComposerTextMetrics(
      height: height,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
    );
  }
}

class _ComposerTextMetrics {
  const _ComposerTextMetrics({
    required this.height,
    required this.topPadding,
    required this.bottomPadding,
  });

  final double height;
  final double topPadding;
  final double bottomPadding;
}

class _ComposerPanelFrame extends StatelessWidget {
  const _ComposerPanelFrame({super.key, required this.panel});

  final ComposerPanel panel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: UiColors.surface,
        border: Border(bottom: BorderSide(color: UiColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: switch (panel.type) {
          ComposerPanelType.list => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: panel.height),
            child: Padding(
              padding: panel.padding,
              child: _ComposerWrapList(panel: panel),
            ),
          ),
          ComposerPanelType.static => SizedBox(
            height: panel.height,
            child: Padding(padding: panel.padding, child: panel.child!),
          ),
        },
      ),
    );
  }
}

class _ComposerWrapList extends StatelessWidget {
  const _ComposerWrapList({required this.panel});

  final ComposerPanel panel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var index = 0; index < panel.itemCount; index++)
            panel.itemBuilder!(context, index),
        ],
      ),
    );
  }
}

class _ComposerContent extends StatelessWidget {
  const _ComposerContent({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (_) => true,
      child: child,
    );
  }
}
