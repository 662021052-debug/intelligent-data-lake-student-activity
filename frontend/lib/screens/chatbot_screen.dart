import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/typing_indicator.dart';
import 'register_activities_screen.dart';

/// Student-facing "ผู้ช่วยอัจฉริยะ" chat screen (Phase 19).
///
/// Talks to POST /chatbot/ask: rules Q&A (RAG), the student's own hours/missing
/// categories, open/required activities, and recommendations. Answers that list
/// activities offer a shortcut to the registration screen.
class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatMessage {
  final String text;
  final bool fromUser;
  final bool referencesActivities;
  _ChatMessage(this.text, {required this.fromUser, this.referencesActivities = false});
}

const _quickPrompts = <String, String>{
  'ชั่วโมงของฉัน': 'ฉันได้กี่ชั่วโมงแล้ว',
  'ขาดหมวดไหน': 'ขาดหมวดไหนบ้าง',
  'กิจกรรมที่เปิดรับ': 'กิจกรรมอะไรเปิดรับสมัครบ้าง',
  'แนะนำกิจกรรม': 'แนะนำกิจกรรมให้หน่อย',
};

class _ChatbotScreenState extends State<ChatbotScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    _ChatMessage(
      'สวัสดีค่ะ ฉันคือผู้ช่วยอัจฉริยะ 🤖\n'
      'ถามเรื่องชั่วโมงกิจกรรม หมวดที่ยังขาด กิจกรรมที่เปิดรับ หรือขอคำแนะนำได้เลยค่ะ',
      fromUser: false,
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String question) async {
    final text = question.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatMessage(text, fromUser: true));
      _sending = true;
      _controller.clear();
    });
    _scrollToBottom();

    try {
      final res = await ApiService.askChatbot(text);
      setState(() {
        _messages.add(_ChatMessage(
          res.answer,
          fromUser: false,
          referencesActivities: res.referencesActivities,
        ));
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage('ขออภัย เกิดข้อผิดพลาด: $e', fromUser: false));
      });
    } finally {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('ผู้ช่วยอัจฉริยะ')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_sending && index == _messages.length) {
                      return const _TypingBubble();
                    }
                    return _MessageBubble(
                      message: _messages[index],
                      onOpenRegister: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterActivitiesScreen()),
                      ),
                    );
                  },
                ),
              ),
              // แถบล่าง (คำถามลัด + ช่องพิมพ์) อยู่ติดขอบล่างเสมอ พื้นหลังต่างจากพื้นที่แชต
              // เพื่อไม่ให้หน้าจอกระโดดเวลาคีย์บอร์ดขึ้นหรือข้อความยาวขึ้น
              Material(
                color: scheme.surfaceContainerLow,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(height: 1),
                      _QuickPrompts(onTap: _sending ? null : _send),
                      _Composer(controller: _controller, sending: _sending, onSend: _send),
                    ],
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

/// รูปประจำตัวของบอท วางไว้ซ้ายของฟองข้อความฝั่งบอททุกอัน
class _BotAvatar extends StatelessWidget {
  const _BotAvatar();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: scheme.primaryContainer,
      child: Icon(Icons.smart_toy, size: 18, color: scheme.onPrimaryContainer),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final VoidCallback onOpenRegister;
  const _MessageBubble({required this.message, required this.onOpenRegister});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fromUser = message.fromUser;
    final bg = fromUser ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = fromUser ? scheme.onPrimary : scheme.onSurface;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: bg,
        // มุมด้านที่ติดกับผู้พูดโค้งน้อยกว่า ทำให้รู้ทันทีว่าใครพูด
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(fromUser ? 16 : 4),
          bottomRight: Radius.circular(fromUser ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(message.text, style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
          if (message.referencesActivities) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onOpenRegister,
                icon: const Icon(Icons.how_to_reg, size: 18),
                label: const Text('ไปหน้าสมัครกิจกรรม'),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!fromUser) ...[
            const _BotAvatar(),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

/// ฟองข้อความ "กำลังพิมพ์" ของบอท (avatar + จุดสามจุดกระพริบ)
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _BotAvatar(),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: const TypingIndicator(),
          ),
        ],
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  final void Function(String question)? onTap;
  const _QuickPrompts({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'คำถามที่ถามบ่อย',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in _quickPrompts.entries)
                ActionChip(
                  label: Text(entry.key),
                  avatar: Icon(
                    Icons.bolt,
                    size: 16,
                    color: onTap == null
                        ? theme.disabledColor
                        : theme.colorScheme.primary,
                  ),
                  backgroundColor: theme.colorScheme.surface,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                  onPressed: onTap == null ? null : () => onTap!(entry.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final void Function(String question) onSend;
  const _Composer({required this.controller, required this.sending, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: sending ? null : onSend,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'พิมพ์คำถามของคุณ...',
                prefixIcon: Icon(Icons.chat_bubble_outline, size: 20),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: sending ? null : () => onSend(controller.text),
            icon: const Icon(Icons.send),
            tooltip: 'ส่ง',
          ),
        ],
      ),
    );
  }
}
