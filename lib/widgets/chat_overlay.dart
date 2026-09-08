import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

const String _geminiApiKey = 'AIzaSyBnmF4HZ12aabmyYl8WpED5GPzfth49F0w';
const String _geminiUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey';

class ChatOverlay extends StatefulWidget {
  const ChatOverlay({super.key});

  @override
  State<ChatOverlay> createState() => _ChatOverlayState();
}

class _ChatOverlayState extends State<ChatOverlay>
    with SingleTickerProviderStateMixin {
  final _auth      = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _inputController  = TextEditingController();
  final _scrollController = ScrollController();

  final List<_Message> _messages = [];
  bool _sending = false;

  late AnimationController _animController;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();

    _messages.add(_Message(
      role: 'assistant',
      text: "Hi! I'm your DiASync AI assistant powered by Gemini. Ask me anything about your glucose levels, insulin, or diabetes management.",
      time: DateTime.now(),
    ));
  }

  @override
  void dispose() {
    _animController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ────────────────────────────────────────────────
  // Send message
  // ────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    _inputController.clear();
    setState(() {
      _messages.add(_Message(role: 'user', text: text, time: DateTime.now()));
      _sending = true;
    });
    _scrollToBottom();

    try {
      // Grab latest glucose reading for context
      final uid = _auth.currentUser?.uid;
      String contextInfo = '';
      if (uid != null) {
        final snap = await _firestore
            .collection('glucoseReadings')
            .where('patientID', isEqualTo: uid)
            
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final latest = snap.docs.first.data();
          final val    = latest['glucoseLevel'];
          final ts     = (latest['timestamp'] as Timestamp?)?.toDate();
          contextInfo =
              'Latest glucose reading: ${val ?? "unknown"} mg/dL at ${ts?.toLocal().toString() ?? "unknown time"}.';
        }
      }

      // System prompt — makes Gemini act as a diabetes assistant
      final systemPrompt = '''You are DiASync AI, a helpful medical assistant 
specializing in diabetes management. You help patients understand their glucose 
levels, insulin dosing, diet, and general diabetes care. Always be supportive, 
clear, and remind users to consult their doctor for medical decisions.
${contextInfo.isNotEmpty ? '\nPatient context: $contextInfo' : ''}''';

      // Build conversation history for Gemini
      // Gemini uses "user" and "model" roles (not "assistant")
      final List<Map<String, dynamic>> geminiHistory = [];

      // Add previous messages as context (last 10)
      final historyMessages = _messages.length > 1
          ? _messages.sublist(1) // skip greeting
          : <_Message>[];
      final recentHistory = historyMessages.length > 10
          ? historyMessages.sublist(historyMessages.length - 10)
          : historyMessages;

      for (final msg in recentHistory) {
        geminiHistory.add({
          'role': msg.role == 'user' ? 'user' : 'model',
          'parts': [{'text': msg.text}],
        });
      }

      // Call Gemini API
      final response = await http.post(
        Uri.parse(_geminiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'system_instruction': {
            'parts': [{'text': systemPrompt}]
          },
          'contents': geminiHistory,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data  = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = data['candidates']?[0]?['content']?['parts']?[0]?['text']
            as String? ?? 'Sorry, I could not generate a response.';
        setState(() {
          _messages.add(_Message(role: 'assistant', text: reply.trim(), time: DateTime.now()));
          _sending = false;
        });
      } else {
        final err = jsonDecode(response.body);
        _addError('API error: ${err['error']?['message'] ?? response.statusCode}');
      }
    } catch (e) {
      _addError('ERROR: ${e.toString()}');
    }

    _scrollToBottom();
  }

  void _addError(String msg) {
    setState(() {
      _messages.add(_Message(role: 'assistant', text: msg, time: DateTime.now(), isError: true));
      _sending = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _handle(),
            _header(),
            const Divider(color: Colors.white10, height: 1),
            Expanded(child: _messageList()),
            if (_sending) _typingIndicator(),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────
  // Widgets
  // ────────────────────────────────────────────────

  Widget _handle() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      width: 40, height: 4,
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF4FC3F7).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: Color(0xFF4FC3F7), size: 20),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DiASync AI',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              Text('Powered by Gemini',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _messageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(_Message msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF4FC3F7).withOpacity(0.18)
              : msg.isError
                  ? Colors.red.withOpacity(0.1)
                  : const Color(0xFF0F1117),
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(16),
            topRight:    const Radius.circular(16),
            bottomLeft:  Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: Border.all(
            color: isUser
                ? const Color(0xFF4FC3F7).withOpacity(0.3)
                : msg.isError
                    ? Colors.red.withOpacity(0.3)
                    : Colors.white10,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(msg.text,
                style: TextStyle(
                    color: msg.isError ? Colors.red.shade300 : Colors.white,
                    fontSize: 14,
                    height: 1.4)),
            const SizedBox(height: 4),
            Text(_formatTime(msg.time),
                style: const TextStyle(color: Colors.white30, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _typingIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 0, 6),
      child: Row(children: [_dot(0), _dot(150), _dot(300)]),
    );
  }

  Widget _dot(int delay) => _AnimatedDot(delay: delay);

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1117),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask about your glucose...',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFF1A1D2E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: _sending ? Colors.white12 : const Color(0xFF4FC3F7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _sending ? Icons.hourglass_empty : Icons.send_rounded,
                color: _sending ? Colors.white38 : Colors.black87,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ────────────────────────────────────────────────
// Data model
// ────────────────────────────────────────────────

class _Message {
  final String   role;
  final String   text;
  final DateTime time;
  final bool     isError;
  const _Message({
    required this.role,
    required this.text,
    required this.time,
    this.isError = false,
  });
}

// ────────────────────────────────────────────────
// Animated typing dots
// ────────────────────────────────────────────────

class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(begin: 0, end: 6)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin: EdgeInsets.only(right: 4, bottom: _anim.value),
        width: 7, height: 7,
        decoration: const BoxDecoration(
            color: Color(0xFF4FC3F7), shape: BoxShape.circle),
      ),
    );
  }
}