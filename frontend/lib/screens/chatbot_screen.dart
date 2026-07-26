import 'package:flutter/material.dart';

import '../services/api_service.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('ผู้ช่วยอัจฉริยะ')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
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
              _QuickPrompts(onTap: _sending ? null : _send),
              const Divider(height: 1),
              _Composer(controller: _controller, sending: _sending, onSend: _send),
            ],
          ),
        ),
      ),
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
    final fromUser = message.fromUser;
    final bg = fromUser ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    final fg = fromUser ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(message.text, style: TextStyle(color: fg)),
            if (message.referencesActivities) ...[
              const SizedBox(height: 8),
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
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _QuickPrompts extends StatelessWidget {
  final void Function(String question)? onTap;
  const _QuickPrompts({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final entry in _quickPrompts.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(entry.key),
                onPressed: onTap == null ? null : () => onTap!(entry.value),
              ),
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
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: sending ? null : onSend,
              decoration: const InputDecoration(
                hintText: 'พิมพ์คำถามของคุณ...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
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
