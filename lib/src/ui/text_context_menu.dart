import 'package:flutter/material.dart';

Widget buildTextFieldContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  ContextMenuButtonItem? itemOfType(ContextMenuButtonType type) {
    for (final item in editableTextState.contextMenuButtonItems) {
      if (item.type == type) return item;
    }
    return null;
  }

  ContextMenuButtonItem localizedItem(
    ContextMenuButtonType type,
    String label,
  ) {
    final item = itemOfType(type);
    return ContextMenuButtonItem(
      type: type,
      label: label,
      onPressed: item?.onPressed,
    );
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      localizedItem(ContextMenuButtonType.cut, '剪切'),
      localizedItem(ContextMenuButtonType.copy, '复制'),
      localizedItem(ContextMenuButtonType.paste, '粘贴'),
      ContextMenuButtonItem(
        label: '删除',
        onPressed: _canDeleteSelection(editableTextState)
            ? () => _deleteSelection(editableTextState)
            : null,
      ),
    ],
  );
}

bool _canDeleteSelection(EditableTextState state) {
  final selection = state.textEditingValue.selection;
  if (!selection.isValid || selection.isCollapsed) return false;
  for (final item in state.contextMenuButtonItems) {
    if (item.type == ContextMenuButtonType.cut) {
      return item.onPressed != null;
    }
  }
  return false;
}

void _deleteSelection(EditableTextState state) {
  final value = state.textEditingValue;
  final selection = value.selection;
  if (!selection.isValid || selection.isCollapsed) return;
  final start = selection.start < selection.end
      ? selection.start
      : selection.end;
  final end = selection.start < selection.end ? selection.end : selection.start;
  final next = value.replaced(TextRange(start: start, end: end), '');
  state.userUpdateTextEditingValue(
    next.copyWith(selection: TextSelection.collapsed(offset: start)),
    SelectionChangedCause.toolbar,
  );
  state.hideToolbar();
}
