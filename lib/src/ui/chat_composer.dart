import 'package:flutter/material.dart';

import 'button.dart';
import 'input.dart';
import 'tokens.dart';

const double _composerControlHeight = Input.defaultHeight;
const double _composerControlOuterHeight = _composerControlHeight + 8;
const double _composerControlVerticalOffset = 2;

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
                    child: Transform.translate(
                      offset: const Offset(0, _composerControlVerticalOffset),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Input(
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
