part of 'home_shell.dart';

extension _HomeShellMessages on _HomeShellState {
  Future<void> _sendText(String value) async {
    final room = _selectedRoom;
    if (room == null || _sending) return;
    final body = value.trimRight();
    if (!canSendComposedMessage(
      body: body,
      type: 'text',
      attachments: const [],
    )) {
      return;
    }

    String? clientMessageId;
    _setHomeState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      final sent = await _messagesController.sendComposedMessage(
        roomId: room.id,
        sender: _currentUser.toSummary(),
        body: body,
        onPending: (pending) {
          clientMessageId = pending.clientMessageId;
          if (!mounted) return;
          _setHomeState(() {
            _messages = _messagesController.patchPendingMessage(
              messages: _messages,
              pending: pending,
            );
            _composerController.clear();
          });
        },
      );
      if (!mounted || _selectedServerId != room.id) return;
      _setHomeState(() {
        _messages = _messagesController.patchSentMessage(
          messages: _messages,
          sent: sent,
        );
      });
      unawaited(_loadServers());
    } catch (error) {
      if (!mounted) return;
      _setHomeState(() {
        _sendError = error.toString();
        if (clientMessageId != null) {
          _messages = _messagesController.patchFailedMessage(
            messages: _messages,
            clientMessageId: clientMessageId!,
          );
        }
      });
    } finally {
      if (mounted) _setHomeState(() => _sending = false);
    }
  }
}
