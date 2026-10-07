import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../application/messaging_controller.dart';
import '../application/messaging_models.dart';
import 'echat_theme.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, required this.controller});

  final MessagingController controller;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

String _formatConversationTime(AppConversation conversation) {
  final value = conversation.lastMessage?.createdAt;
  if (value == null) return '';
  final now = DateTime.now();
  final difference = now.difference(value);
  if (DateUtils.isSameDay(value, now)) {
    return DateFormat('h:mm a').format(value);
  }
  if (difference.inDays.abs() < 7) return DateFormat('EEE').format(value);
  return DateFormat('MMM d').format(value);
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
  Widget build(BuildContext context) {
    final connectionStatus = widget.controller.connectionStatus;
    return Scaffold(
      backgroundColor: EchatColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: EchatColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.shield_rounded,
                size: 20,
                color: EchatColors.accent,
              ),
            ),
            const SizedBox(width: EchatSpacing.md),
            const Text('eChat'),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('sync-conversations'),
            tooltip: 'Synchronize conversations',
            onPressed: _synchronize,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              EchatSpacing.lg,
              EchatSpacing.sm,
              EchatSpacing.lg,
              EchatSpacing.md,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Messages',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: EchatSpacing.xs),
                          Text(
                            'Your conversations',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: EchatColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (connectionStatus != AppConnectionStatus.connected)
            _RelayStatusBanner(status: connectionStatus),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<AppConversation>>(
                future: _conversations,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 96),
                        EchatEmptyState(
                          icon: Icons.error_outline_rounded,
                          title: 'Conversations unavailable',
                          message:
                              'Your conversation list could not be loaded. Pull to try again.',
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final conversations = snapshot.data!;
                  if (conversations.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 72),
                        EchatEmptyState(
                          icon: Icons.forum_outlined,
                          title: 'No conversations yet',
                          message:
                              'When you start a conversation with a contact, it will appear here.',
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    key: const Key('conversation-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: EchatSpacing.lg,
                      vertical: EchatSpacing.md,
                    ),
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: EchatSpacing.sm),
                    itemBuilder: (context, index) {
                      final conversation = conversations[index];
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: _ConversationCard(
                            conversation: conversation,
                            onTap: () => _open(conversation),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayStatusBanner extends StatelessWidget {
  const _RelayStatusBanner({required this.status});

  final AppConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final details = switch (status) {
      AppConnectionStatus.notConfigured => (
        title: 'Relay not configured',
        message:
            'Pending messages remain encrypted in your local outbox until a relay is configured.',
        icon: Icons.cloud_off_rounded,
        color: EchatColors.warning,
      ),
      AppConnectionStatus.disconnected => (
        title: 'Offline · relay unavailable',
        message:
            'Pending messages remain encrypted in your local outbox until the connection returns.',
        icon: Icons.cloud_off_rounded,
        color: EchatColors.warning,
      ),
      AppConnectionStatus.connecting => (
        title: 'Connecting to relay',
        message:
            'Pending messages remain in your encrypted local outbox while connecting.',
        icon: Icons.sync_rounded,
        color: EchatColors.accent,
      ),
      AppConnectionStatus.connected => (
        title: '',
        message: '',
        icon: Icons.cloud_done_rounded,
        color: EchatColors.success,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        EchatSpacing.lg,
        0,
        EchatSpacing.lg,
        EchatSpacing.md,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Semantics(
            container: true,
            label: '${details.title}. ${details.message}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(EchatSpacing.md),
              decoration: BoxDecoration(
                color: details.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: details.color.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(details.icon, color: details.color),
                  const SizedBox(width: EchatSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          details.title,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: details.color,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: EchatSpacing.xs),
                        Text(
                          details.message,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: EchatColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation, required this.onTap});

  final AppConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final message = conversation.lastMessage;
    final title = conversation.displayAlias.trim().isEmpty
        ? conversation.peerDeviceId
        : conversation.displayAlias;
    final messageStatus = message == null
        ? null
        : _messageStatusPresentation(message.status);
    final preview = message == null
        ? 'No messages yet'
        : message.isOutgoing
        ? 'You: ${message.body}'
        : message.body;
    final sessionStatus = switch (conversation.sessionStatus) {
      AppSessionStatus.notStarted => 'No session',
      AppSessionStatus.requestPending => 'Session request pending',
      AppSessionStatus.responsePendingDelivery =>
        'Session response awaiting delivery',
      AppSessionStatus.established => 'Session established',
      AppSessionStatus.closed => 'Session closed',
      AppSessionStatus.restoredNeedsReview => 'Session review required',
    };
    final semanticLabel = StringBuffer('Open conversation with $title.')
      ..write(' ${message == null ? sessionStatus : 'Last message: $preview.'}')
      ..write(
        ' ${messageStatus?.label ?? sessionStatus}. Trust: ${_trustLabel(conversation.trustStatus)}.',
      );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: semanticLabel.toString(),
        child: InkWell(
          key: Key('conversation-${conversation.sessionId}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(EchatSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: EchatColors.accent.withValues(
                        alpha: 0.12,
                      ),
                      child: Text(
                        title.characters.first.toUpperCase(),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: EchatColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(width: EchatSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (message != null) ...[
                                const SizedBox(width: EchatSpacing.sm),
                                Text(
                                  _formatConversationTime(conversation),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: EchatColors.textSecondary,
                                      ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: EchatSpacing.xs),
                          EchatTrustBadge(status: conversation.trustStatus),
                        ],
                      ),
                    ),
                    const SizedBox(width: EchatSpacing.sm),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: EchatColors.muted,
                      semanticLabel: 'Open conversation',
                    ),
                  ],
                ),
                const SizedBox(height: EchatSpacing.md),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: message == null
                        ? EchatColors.muted
                        : EchatColors.textSecondary,
                  ),
                ),
                const SizedBox(height: EchatSpacing.md),
                Row(
                  children: [
                    if (messageStatus != null) ...[
                      Icon(
                        messageStatus.icon,
                        size: 16,
                        color: messageStatus.color,
                      ),
                      const SizedBox(width: EchatSpacing.xs),
                      Expanded(
                        child: Text(
                          messageStatus.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: messageStatus.color),
                        ),
                      ),
                    ] else
                      Expanded(
                        child: Text(
                          sessionStatus,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: EchatColors.textSecondary),
                        ),
                      ),
                    if (conversation.pendingMessageCount > 0)
                      EchatStatusChip(
                        label: '${conversation.pendingMessageCount} pending',
                        color: EchatColors.warning,
                        icon: Icons.schedule_rounded,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

({String label, Color color, IconData icon}) _messageStatusPresentation(
  AppMessageStatus status,
) => switch (status) {
  AppMessageStatus.pending => (
    label: 'Pending in encrypted outbox',
    color: EchatColors.warning,
    icon: Icons.schedule_rounded,
  ),
  AppMessageStatus.submittedToRelay => (
    label: 'Submitted to relay',
    color: EchatColors.accent,
    icon: Icons.cloud_upload_outlined,
  ),
  AppMessageStatus.receivedLocally => (
    label: 'Received locally',
    color: EchatColors.success,
    icon: Icons.mark_chat_read_outlined,
  ),
  AppMessageStatus.failed => (
    label: 'Failed',
    color: EchatColors.danger,
    icon: Icons.error_outline_rounded,
  ),
};

String _trustLabel(AppTrustStatus status) => switch (status) {
  AppTrustStatus.unverified => 'Unverified',
  AppTrustStatus.verified => 'Verified',
  AppTrustStatus.identityChanged => 'Identity changed',
  AppTrustStatus.revoked => 'Revoked',
};

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

  String get _contactName {
    final alias = widget.conversation.displayAlias.trim();
    return alias.isEmpty ? widget.conversation.peerDeviceId : alias;
  }

  @override
  void initState() {
    super.initState();
    _messages = widget.controller.messages(widget.conversation.sessionId);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
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
      _statusMessage = result.receivedLocally > 0 || result.submittedToRelay > 0
          ? 'Sync complete: ${result.submittedToRelay} submitted, ${result.receivedLocally} received.'
          : 'Sync idle: no new relay activity.';
    } on Object {
      _statusMessage =
          'Sync failed. Local pending messages remain encrypted and pending.';
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
    backgroundColor: EchatColors.background,
    appBar: AppBar(
      title: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: EchatColors.accent.withValues(alpha: 0.12),
            child: Text(
              _contactName.characters.first.toUpperCase(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: EchatColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: EchatSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _contactName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.conversation.peerDeviceId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: EchatColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                : const Icon(Icons.sync_rounded),
          ),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          _SecurityBanner(conversation: widget.conversation),
          if (widget.controller.connectionStatus !=
              AppConnectionStatus.connected)
            _RelayStatusBanner(status: widget.controller.connectionStatus),
          Expanded(
            child: FutureBuilder<List<AppMessage>>(
              future: _messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: EchatEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Message history unavailable',
                      message:
                          'Pull down to try loading your local messages again.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(EchatSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const EchatEmptyState(
                            icon: Icons.chat_bubble_outline_rounded,
                            title: 'No messages yet',
                            message:
                                'Messages are stored locally in encrypted storage and encrypted before relay submission.',
                          ),
                          if (!_canSend) ...[
                            const SizedBox(height: EchatSpacing.md),
                            Text(
                              'Messaging is blocked until trust and session setup are complete.',
                              key: const Key('chat-blocked-message'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: EchatColors.warning),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollToBottom(),
                );
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: ListView.builder(
                      key: const Key('message-list'),
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: EchatSpacing.lg,
                        vertical: EchatSpacing.md,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => _MessageBubble(
                        message: messages[index],
                        busy: _busy || _syncing,
                        onRetry: () => _retryMessage(messages[index].id),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_statusMessage != null)
            Container(
              key: const Key('send-status'),
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 820),
              margin: const EdgeInsets.symmetric(
                horizontal: EchatSpacing.lg,
                vertical: EchatSpacing.sm,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: EchatSpacing.md,
                vertical: EchatSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: EchatColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: EchatColors.border),
              ),
              child: Text(_statusMessage!),
            ),
          _MessageComposer(
            controller: _messageController,
            enabled: _canSend && !_busy,
            busy: _busy,
            onChanged: (_) => setState(() {}),
            onSend: _send,
          ),
        ],
      ),
    ),
  );
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.conversation});

  final AppConversation conversation;

  @override
  Widget build(BuildContext context) {
    final trustDetails = switch (conversation.trustStatus) {
      AppTrustStatus.verified => (
        label: 'Identity verified',
        color: EchatColors.success,
        icon: Icons.verified_user_rounded,
      ),
      AppTrustStatus.unverified => (
        label: 'Identity not verified',
        color: EchatColors.warning,
        icon: Icons.gpp_maybe_rounded,
      ),
      AppTrustStatus.identityChanged => (
        label: 'Identity changed — re-verification required',
        color: EchatColors.warning,
        icon: Icons.warning_amber_rounded,
      ),
      AppTrustStatus.revoked => (
        label: 'Contact revoked',
        color: EchatColors.danger,
        icon: Icons.block_rounded,
      ),
    };
    final sessionLabel = _sessionLabel(conversation.sessionStatus);
    final headline =
        conversation.trustStatus == AppTrustStatus.verified &&
            conversation.sessionStatus == AppSessionStatus.established
        ? 'Verified · session established'
        : trustDetails.label;
    return Container(
      key: const Key('chat-security-state'),
      margin: const EdgeInsets.fromLTRB(
        EchatSpacing.lg,
        EchatSpacing.md,
        EchatSpacing.lg,
        EchatSpacing.sm,
      ),
      padding: const EdgeInsets.all(EchatSpacing.md),
      decoration: BoxDecoration(
        color: EchatColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: trustDetails.color.withValues(alpha: 0.35)),
      ),
      child: Semantics(
        container: true,
        label: '$headline. $sessionLabel.',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(trustDetails.icon, color: trustDetails.color),
            const SizedBox(width: EchatSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: trustDetails.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: EchatSpacing.xs),
                  Text(
                    sessionLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: EchatColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  final AppMessage message;
  final bool busy;
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
      AppMessageStatus.failed => 'Failed',
    };
    final statusColor = switch (message.status) {
      AppMessageStatus.pending => EchatColors.warning,
      AppMessageStatus.submittedToRelay => EchatColors.accent,
      AppMessageStatus.receivedLocally => EchatColors.textSecondary,
      AppMessageStatus.failed => EchatColors.danger,
    };
    final tinted = message.isOutgoing
        ? EchatColors.surfaceHigh
        : EchatColors.surface;
    final messageRole = message.isOutgoing ? 'You' : 'Contact';
    final timestamp = DateFormat('h:mm a').format(message.createdAt.toLocal());
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width < 500
              ? MediaQuery.sizeOf(context).width * 0.84
              : 560,
        ),
        child: Container(
          key: ValueKey<String>('message-${message.id}'),
          margin: const EdgeInsets.symmetric(vertical: EchatSpacing.xs),
          padding: const EdgeInsets.all(EchatSpacing.md),
          decoration: BoxDecoration(
            color: tinted,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(message.isOutgoing ? 18 : 5),
              bottomRight: Radius.circular(message.isOutgoing ? 5 : 18),
            ),
            border: Border.all(color: EchatColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: '$messageRole message: ${message.body}',
                child: Text(
                  message.body,
                  key: ValueKey<String>('message-body-${message.id}'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EchatColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: EchatSpacing.sm),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: EchatSpacing.xs,
                runSpacing: EchatSpacing.xs,
                children: [
                  if (message.isOutgoing)
                    Icon(
                      switch (message.status) {
                        AppMessageStatus.pending => Icons.schedule_rounded,
                        AppMessageStatus.submittedToRelay =>
                          Icons.cloud_upload_outlined,
                        AppMessageStatus.receivedLocally => Icons.check_rounded,
                        AppMessageStatus.failed => Icons.error_outline_rounded,
                      },
                      size: 14,
                      color: statusColor,
                    ),
                  Text(
                    status,
                    key: ValueKey<String>('message-status-${message.id}'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    timestamp,
                    key: ValueKey<String>('message-time-${message.id}'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: EchatColors.textSecondary,
                    ),
                  ),
                  if (message.isOutgoing &&
                      message.status == AppMessageStatus.failed)
                    Tooltip(
                      message: 'Retry failed message',
                      child: TextButton(
                        key: ValueKey<String>('retry-message-${message.id}'),
                        onPressed: busy ? null : onRetry,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: EchatSpacing.sm,
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
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

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = enabled && controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EchatSpacing.md,
              EchatSpacing.sm,
              EchatSpacing.md,
              EchatSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Semantics(
                    label: 'Message input',
                    enabled: enabled,
                    child: TextField(
                      key: const Key('message-input'),
                      controller: controller,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      onChanged: onChanged,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: enabled
                            ? 'Write a message'
                            : 'Session not ready',
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: EchatSpacing.md,
                          vertical: EchatSpacing.md,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: EchatSpacing.sm),
                Semantics(
                  label: 'Send message',
                  button: true,
                  enabled: canSend && !busy,
                  child: IconButton.filled(
                    key: const Key('send-message'),
                    tooltip: 'Send message',
                    onPressed: canSend && !busy ? onSend : null,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sessionLabel(AppSessionStatus status) => switch (status) {
  AppSessionStatus.notStarted => 'No session',
  AppSessionStatus.requestPending => 'Session request pending exchange',
  AppSessionStatus.responsePendingDelivery =>
    'Session response awaiting delivery',
  AppSessionStatus.established => 'Session established',
  AppSessionStatus.closed => 'Session closed',
  AppSessionStatus.restoredNeedsReview => 'Restored session requires review',
};
