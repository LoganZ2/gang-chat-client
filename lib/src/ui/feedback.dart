import 'package:flutter/material.dart';

import 'button.dart';
import 'tokens.dart';

class Toast extends StatelessWidget {
  const Toast({super.key, required this.message, this.icon});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: UiColors.surface,
          borderRadius: BorderRadius.circular(UiRadii.lg),
          border: Border.all(color: UiColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: UiColors.accent),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: UiColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DialogFrame extends StatelessWidget {
  const DialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.actions = const [],
    this.maxWidth = 480,
  });

  final String title;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: UiColors.surface,
            borderRadius: BorderRadius.circular(UiRadii.lg),
            border: Border.all(color: UiColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: UiColors.accent),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: Text(title, style: UiTypography.title)),
                  ],
                ),
                const SizedBox(height: 14),
                child,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (final action in actions) ...[
                        action,
                        if (action != actions.last) const SizedBox(width: 10),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showUiDialog(
  BuildContext context, {
  required String title,
  required Widget child,
  IconData? icon,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => DialogFrame(
      title: title,
      icon: icon,
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          tone: ButtonTone.primary,
          child: const Text('Done'),
        ),
      ],
      child: child,
    ),
  );
}
