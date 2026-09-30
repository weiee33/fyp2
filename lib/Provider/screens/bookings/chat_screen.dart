import 'package:flutter/material.dart';
import '../../services/booking_service.dart';

class ChatScreen extends StatefulWidget {
  final String bookingId;
  const ChatScreen({super.key, required this.bookingId});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _service = BookingService();
  final _msg = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _messages = await _service.getChatMessages(widget.bookingId);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    if (_msg.text.trim().isEmpty) return;
    await _service.sendMessage(widget.bookingId, _msg.text.trim());
    _msg.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      return Card(
                        child: ListTile(
                          title: Text(m['message'] ?? ''),
                          subtitle: Text(m['created_at'] ?? ''),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msg,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                          onPressed: _send, child: const Text('Send')),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}