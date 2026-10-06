import 'package:flutter/material.dart';

import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.controller});

  final MessagingController controller;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

String _conversationSubtitle(AppConversation conversation) {
  final last = conversation.lastMessage;
  if (last != null) return last.body;
  return _sessionLabel(conversation.sessionStatus);
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
              result.receivedLocally > 0 || result.submittedToRelay > 0
                  ? 'Sync complete: ${result.submittedToRelay} submitted, ${result.receivedLocally} received.'
                  : 'Sync idle: no new relay activity.',
            ),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sync failed. Local pending messages remain encrypted and pending.',
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
              final statusBadge = switch (conversation.sessionStatus) {
                AppSessionStatus.established => const Icon(Icons.lock_outline),
                AppSessionStatus.requestPending => const Icon(Icons.pending_outlined),
                AppSessionStatus.responsePendingDelivery => const Icon(Icons.sync_outlined),
                AppSessionStatus.closed => const Icon(Icons.block_outlined),
                AppSessionStatus.restoredNeedsReview => const Icon(Icons.warning_amber_rounded),
                AppSessionStatus.notStarted => const Icon(Icons.person_outline),
              };
              return ListTile(
                key: Key('conversation-${conversation.sessionId}'),
                leading: CircleAvatar(
                  child: Text(conversation.displayAlias.characters.first),
                ),
                title: Text(conversation.displayAlias),
                subtitle: Text(
                  _conversationSubtitle(conversation),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (conversation.pendingMessageCount > 0)
                      Badge(
                        label: Text('${conversation.pendingMessageCount}'),
                        child: const Icon(Icons.schedule),
                      )
                    else
                      statusBadge,
                  ],
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
  final ScrollController _scrollController = ScrollController();
  late Future<List<AppMessage>> _messages;
  bool _busy = false;
  bool _syncing = false;
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
    final text = _messageController.text.trim();
    if (text.isEmpty || !_canSend || _busy) return;
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
          'Send failed. Trust and session state were not ready for a new message.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryMessage(String messageId) async {
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      await widget.controller.retryMessage(messageId);
      await _refresh();
      _statusMessage =
          'Retry accepted. The message remains encrypted until the relay accepts it.';
    } on Object {
      _statusMessage = 'Retry failed. The message remains pending or blocked.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _synchronize() async {
    setState(() {
      _syncing = true;
      _statusMessage = null;
    });
    try {
      final result = await widget.controller.synchronize();
      await _refresh();
      _statusMessage =
          result.receivedLocally > 0 || result.submittedToRelay > 0
              ? 'Sync complete: ${result.submittedToRelay} submitted, ${result.receivedLocally} received.'
              : 'Sync idle: no new relay activity.';
    } on Object {
      _statusMessage = 'Sync failed. Local pending messages remain encrypted and pending.';
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.conversation.displayAlias),
      actions: [
        Semantics(
          label: 'Synchronize messages',
          button: true,
          enabled: !(_busy || _syncing),
          child: IconButton(
            key: const Key('sync-chat'),
            tooltip: 'Synchronize',
            onPressed: _busy || _syncing ? null : _synchronize,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
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
              WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
              return ListView.builder(
                key: const Key('message-list'),
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: messages.length,
                itemBuilder: (context, index) => _MessageBubble(
                  message: messages[index],
                  onRetry: () => _retryMessage(messages[index].id),
                ),
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
                  child: Semantics(
                    label: 'Message input',
                    enabled: _canSend && !_busy,
                    child: TextField(
                      key: const Key('message-input'),
                      controller: _messageController,
                      enabled: _canSend && !_busy,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        hintText: _canSend ? 'Message' : 'Session not ready',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: 'Send message',
                  button: true,
                  enabled: _canSend && !_busy && _messageController.text.trim().isNotEmpty,
                  child: IconButton.filled(
                    key: const Key('send-message'),
                    tooltip: 'Send message',
                    onPressed: _canSend && !_busy && _messageController.text.trim().isNotEmpty
                        ? _send
                        : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
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
  const _MessageBubble({required this.message, required this.onRetry});

  final AppMessage message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final alignment = message.isOutgoing
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final status = switch (message.status) {
      AppMessageStatus.pending => 'Pending in encrypted outbox',
      AppMessageStatus.submittedToRelay => 'Submitted to relay',
      AppMessageStatus.receivedLocally => 'Received on this device',
      AppMessageStatus.failed => 'Failed; retry available',
    };
    final tinted = message.isOutgoing
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHigh;
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          key: Key('message-${message.id}'),
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tinted,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(message.body),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  if (message.isOutgoing && message.status == AppMessageStatus.failed)
                    TextButton(
                      key: Key('retry-message-${message.id}'),
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                ],
              ),
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
