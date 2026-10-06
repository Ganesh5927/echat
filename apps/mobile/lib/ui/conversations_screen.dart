import 'package:flutter/material.dart';

import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.controller});

  final MessagingController controller;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late Future<List<AppConversation>> _conversations;

  @override
  void initState() {
    super.initState();
    _conversations = widget.controller.conversations();
  }

  Future<void> _refresh() async {
    setState(() => _conversations = widget.controller.conversations());
  }

  Future<void> _open(AppConversation conversation) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          controller: widget.controller,
          conversation: conversation,
        ),
      ),
    );
    await _refresh();
  }

  Future<void> _synchronize() async {
    try {
      final result = await widget.controller.synchronize();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Submitted ${result.submittedToRelay}; received ${result.receivedLocally}.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sync is unavailable. Pending messages remain local.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Conversations'),
      actions: [
        IconButton(
          key: const Key('sync-conversations'),
          tooltip: 'Synchronize',
          onPressed: _synchronize,
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<AppConversation>>(
        future: _conversations,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Conversations unavailable'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final conversations = snapshot.data!;
          if (conversations.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 180),
                Icon(Icons.forum_outlined, size: 44),
                SizedBox(height: 12),
                Center(child: Text('No conversations yet')),
              ],
            );
          }
          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conversation = conversations[index];
              final last = conversation.lastMessage;
              return ListTile(
                key: Key('conversation-${conversation.sessionId}'),
                leading: CircleAvatar(
                  child: Text(conversation.displayAlias.characters.first),
                ),
                title: Text(conversation.displayAlias),
                subtitle: Text(
                  last?.body ?? _sessionLabel(conversation.sessionStatus),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: conversation.pendingMessageCount == 0
                    ? Text(_sessionLabel(conversation.sessionStatus))
                    : Badge(
                        label: Text('${conversation.pendingMessageCount}'),
                        child: const Icon(Icons.schedule),
                      ),
                onTap: () => _open(conversation),
              );
            },
          );
        },
      ),
    ),
  );
}

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.controller,
    required this.conversation,
  });

  final MessagingController controller;
  final AppConversation conversation;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final TextEditingController _messageController = TextEditingController();
  late Future<List<AppMessage>> _messages;
  bool _busy = false;
  String? _statusMessage;

  bool get _canSend =>
      widget.conversation.trustStatus == AppTrustStatus.verified &&
      widget.conversation.sessionStatus == AppSessionStatus.established;

  @override
  void initState() {
    super.initState();
    _messages = widget.controller.messages(widget.conversation.sessionId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(
      () =>
          _messages = widget.controller.messages(widget.conversation.sessionId),
    );
  }

  Future<void> _send() async {
    final text = _messageController.text;
    if (text.trim().isEmpty || !_canSend || _busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await widget.controller.sendText(
        sessionId: widget.conversation.sessionId,
        peerDeviceId: widget.conversation.peerDeviceId,
        text: text,
      );
      _messageController.clear();
      await _refresh();
      _statusMessage =
          widget.controller.connectionStatus == AppConnectionStatus.connected
          ? 'Submitted to relay; recipient delivery is not confirmed.'
          : 'Saved to encrypted outbox; pending connection.';
    } on Object {
      _statusMessage =
          'Message was not queued. Check trust and session status.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _synchronize() async {
    setState(() => _busy = true);
    try {
      final result = await widget.controller.synchronize();
      await _refresh();
      _statusMessage =
          'Submitted ${result.submittedToRelay}; received ${result.receivedLocally}; duplicates acknowledged ${result.duplicatesAcknowledged}.';
    } on Object {
      _statusMessage = 'Sync unavailable; queued messages remain pending.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.conversation.displayAlias),
      actions: [
        IconButton(
          key: const Key('sync-chat'),
          tooltip: 'Synchronize',
          onPressed: _busy ? null : _synchronize,
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: Column(
      children: [
        _SecurityBanner(conversation: widget.conversation),
        if (widget.controller.connectionStatus != AppConnectionStatus.connected)
          const ListTile(
            key: Key('offline-banner'),
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline or relay unavailable'),
            subtitle: Text('New messages stay in the encrypted local outbox.'),
          ),
        Expanded(
          child: FutureBuilder<List<AppMessage>>(
            future: _messages,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Message history unavailable'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final messages = snapshot.data!;
              if (messages.isEmpty) {
                return Center(
                  child: Text(
                    _canSend
                        ? 'No messages yet'
                        : 'Messaging is blocked until trust and session setup are complete.',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return ListView.builder(
                key: const Key('message-list'),
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) =>
                    _MessageBubble(message: messages[index]),
              );
            },
          ),
        ),
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(_statusMessage!, key: const Key('send-status')),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('message-input'),
                    controller: _messageController,
                    enabled: _canSend && !_busy,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _canSend ? 'Message' : 'Session not ready',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const Key('send-message'),
                  tooltip: 'Send message',
                  onPressed: _canSend && !_busy ? _send : null,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.conversation});

  final AppConversation conversation;

  @override
  Widget build(BuildContext context) {
    final trusted = conversation.trustStatus == AppTrustStatus.verified;
    final established =
        conversation.sessionStatus == AppSessionStatus.established;
    return ListTile(
      key: const Key('chat-security-status'),
      leading: Icon(
        trusted && established ? Icons.lock_outline : Icons.gpp_maybe_outlined,
      ),
      title: Text(_trustLabel(conversation.trustStatus)),
      subtitle: Text(_sessionLabel(conversation.sessionStatus)),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AppMessage message;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isOutgoing
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final status = switch (message.status) {
      AppMessageStatus.pending => 'Pending in encrypted outbox',
      AppMessageStatus.submittedToRelay => 'Submitted to relay',
      AppMessageStatus.receivedLocally => 'Received on this device',
    };
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          key: Key('message-${message.id}'),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(message.body),
              const SizedBox(height: 6),
              Text(status, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

String _trustLabel(AppTrustStatus status) => switch (status) {
  AppTrustStatus.unverified => 'Unverified contact',
  AppTrustStatus.verified => 'Verified contact',
  AppTrustStatus.identityChanged => 'Identity changed',
  AppTrustStatus.revoked => 'Contact revoked',
};

String _sessionLabel(AppSessionStatus status) => switch (status) {
  AppSessionStatus.notStarted => 'No session',
  AppSessionStatus.requestPending => 'Session request pending exchange',
  AppSessionStatus.responsePendingDelivery =>
    'Session response awaiting delivery',
  AppSessionStatus.established => 'Session established',
  AppSessionStatus.closed => 'Session closed',
  AppSessionStatus.restoredNeedsReview => 'Restored session requires review',
};
