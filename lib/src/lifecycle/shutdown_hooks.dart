import 'dart:async';

/// Application-wide registry of async cleanup callbacks that must run before
/// the process exits. Used so that `window_manager`'s prevent-close hook can
/// flush in-flight work owned by deeply nested widgets (e.g. leaving a live
/// voice session) before destroying the window.
///
/// Hooks run in registration order. Each hook is best-effort: an exception
/// from one hook does not stop the others. A global timeout is applied at
/// the call site to avoid hanging the close button on a wedged backend.
class ShutdownHooks {
  ShutdownHooks._();

  static final List<Future<void> Function()> _hooks = [];

  /// Register a cleanup callback. Returns a token that can be passed to
  /// [unregister] to remove this exact callback.
  static Object register(Future<void> Function() hook) {
    _hooks.add(hook);
    return hook;
  }

  static void unregister(Object token) {
    if (token is Future<void> Function()) {
      _hooks.remove(token);
    }
  }

  /// Run every registered hook. Caller is expected to wrap this with their
  /// own timeout. Hooks fire in registration order, but exceptions from one
  /// hook do not block the others.
  static Future<void> runAll() async {
    final snapshot = List<Future<void> Function()>.from(_hooks);
    for (final hook in snapshot) {
      try {
        await hook();
      } catch (_) {
        // swallow — shutdown is best-effort
      }
    }
  }
}
