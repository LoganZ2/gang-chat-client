import 'package:flutter/material.dart';

import 'button.dart';
import 'input.dart';
import 'tokens.dart';

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
    this.selected = false,
    this.alignment = ComposerActionAlignment.leading,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? tooltip;
  final ComposerPanel? panel;
  final VoidCallback? onPressed;
  final ButtonTone tone;
  final bool selected;

  /// Where the action sits on the button row below the input. Trailing actions
  /// (typically send) are pinned to the far right.
  final ComposerActionAlignment alignment;

  bool get opensPanel => panel != null;
}

enum ComposerActionAlignment { leading, trailing }

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
    this.hintText = '输入消息',
    this.minLines = 1,
    this.maxLines = 5,
    this.onSubmitted,
    this.onChanged,
    this.attachments,
  });

  final List<ComposerAction> actions;
  final TextEditingController? controller;
  final String hintText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// Optional strip rendered above the input, used to show files staged for
  /// the next message. Null (or empty) leaves the composer unchanged.
  final Widget? attachments;

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
  void dispose() {
    _inputFocusNode.dispose();
    super.dispose();
  }

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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: openPanel == null
                          ? Input(
                              controller: widget.controller,
                              focusNode: _inputFocusNode,
                              hintText: widget.hintText,
                              minLines: widget.minLines,
                              maxLines: widget.maxLines,
                              onSubmitted: widget.onSubmitted,
                              onChanged: widget.onChanged,
                            )
                          : _ComposerPanelFrame(
                              key: ValueKey(openAction!.id),
                              panel: openPanel,
                            ),
                    ),
                  ),
                  if (widget.attachments != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: widget.attachments,
                    ),
                  if (widget.actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: _ComposerActionRow(
                        actions: widget.actions,
                        openActionId: _openActionId,
                        onAction: _handleAction,
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
    // Trailing actions (typically send) are pinned to the far right; the rest
    // stay grouped on the left.
    final leading = [
      for (final action in actions)
        if (action.alignment == ComposerActionAlignment.leading) action,
    ];
    final trailing = [
      for (final action in actions)
        if (action.alignment == ComposerActionAlignment.trailing) action,
    ];

    return Row(
      children: [
        for (var index = 0; index < leading.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          _ComposerActionButton(
            action: leading[index],
            selected:
                leading[index].selected || leading[index].id == openActionId,
            onAction: onAction,
          ),
        ],
        const Spacer(),
        for (var index = 0; index < trailing.length; index++) ...[
          if (index > 0) const SizedBox(width: 8),
          _ComposerActionButton(
            action: trailing[index],
            selected:
                trailing[index].selected || trailing[index].id == openActionId,
            onAction: onAction,
          ),
        ],
      ],
    );
  }
}

class _ComposerActionButton extends StatelessWidget {
  const _ComposerActionButton({
    required this.action,
    required this.selected,
    required this.onAction,
  });

  final ComposerAction action;
  final bool selected;
  final ValueChanged<ComposerAction> onAction;

  @override
  Widget build(BuildContext context) {
    return ButtonIcon(
      tooltip: action.tooltip ?? action.label,
      icon: Icon(action.icon),
      tone: action.tone,
      selected: selected,
      onPressed: () => onAction(action),
    );
  }
}

class _ComposerPanelFrame extends StatelessWidget {
  const _ComposerPanelFrame({super.key, required this.panel});

  final ComposerPanel panel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: UiColors.surface,
        borderRadius: BorderRadius.circular(UiRadii.md),
        border: Border.all(color: UiColors.border),
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
