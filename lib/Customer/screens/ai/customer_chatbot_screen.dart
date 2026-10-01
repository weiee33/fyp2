import 'package:flutter/material.dart';
import '../../core/customer_theme.dart';

class CustomerChatbotScreen extends StatefulWidget {
  const CustomerChatbotScreen({super.key});

  @override
  State<CustomerChatbotScreen> createState() => _CustomerChatbotScreenState();
}

class _CustomerChatbotScreenState extends State<CustomerChatbotScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'bot',
      'text': 'Hello! I am your Local Life AI Triage Assistant. You can describe any household problem (e.g. "my bathroom pipe is bursting" or "aircon is leaking dirty water") and I will diagnose it and match the nearest verified technician.',
      'category': null,
    },
  ];

  bool _isTyping = false;

  void _handleSend() {
    final query = _msgController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': query});
      _isTyping = true;
    });
    _msgController.clear();

    // AI Intent Triage logic (prepared for Gemini API integration)
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      String botReply = "I understand you are having an issue. Let me route you to our verified specialists.";
      String? matchedCat;

      final lower = query.toLowerCase();
      if (lower.contains('pipe') || lower.contains('sink') || lower.contains('leak') || lower.contains('clog')) {
        botReply = "🚨 Emergency Issue Detected: Hydraulic Plumbing Leak.\nRecommended Action: Shut off main stopcock valve. I have filtered top-rated emergency plumbers near you.";
        matchedCat = "Plumbing";
      } else if (lower.contains('aircon') || lower.contains('cool') || lower.contains('water drop')) {
        botReply = "❄️ Air-Conditioning Servicing required: Likely blocked drain pipe or chemical gas deficit. Recommend 1-Hour Chemical Wash technician.";
        matchedCat = "Aircon";
      } else if (lower.contains('wire') || lower.contains('blackout') || lower.contains('spark') || lower.contains('electric')) {
        botReply = "⚡ High Hazard: Electrical Trip / Short Circuit. Recommended Suruhanjaya Tenaga certified electricians dispatched immediately.";
        matchedCat = "Electrical";
      }

      setState(() {
        _isTyping = false;
        _messages.add({
          'sender': 'bot',
          'text': botReply,
          'category': matchedCat,
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CustomerTheme.lightTheme,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, color: CustomerTheme.primary, size: 20),
              SizedBox(width: 8),
              Text('AI Triage Assistant'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (ctx, i) {
                  final msg = _messages[i];
                  final isUser = msg['sender'] == 'user';
                  final cat = msg['category'];

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isUser ? CustomerTheme.primary : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isUser ? 16 : 4),
                          bottomRight: Radius.circular(isUser ? 4 : 16),
                        ),
                        border: isUser ? null : Border.all(color: CustomerTheme.borderColor),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg['text'],
                            style: TextStyle(
                              color: isUser ? Colors.white : CustomerTheme.textPrimary,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                          if (cat != null) ...[
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context, cat);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: CustomerTheme.primarySurface,
                                foregroundColor: CustomerTheme.primaryDark,
                                elevation: 0,
                                minimumSize: const Size.fromHeight(36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                              label: Text('View $cat Providers Now', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_isTyping)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    SizedBox(width: 16),
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: CustomerTheme.primary)),
                    SizedBox(width: 8),
                    Text('Gemini AI analyzing request...', style: TextStyle(fontSize: 12, color: CustomerTheme.textSecondary)),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        onSubmitted: (_) => _handleSend(),
                        decoration: InputDecoration(
                          hintText: 'Type your repair problem...',
                          fillColor: CustomerTheme.background,
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: CustomerTheme.primary,
                      radius: 22,
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: _handleSend,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}