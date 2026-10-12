import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'chat_service.dart';

class ChatPhoto extends StatefulWidget {
  final String path;
  final ChatService service;
  const ChatPhoto({super.key, required this.path, required this.service});
  @override
  State<ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<ChatPhoto> {
  late Future<Uint8List> _bytes = widget.service.photo(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () =>
              setState(() => _bytes = widget.service.photo(widget.path)),
          icon: const Icon(Icons.refresh),
          label: const Text('Reload photo'),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 200,
          height: 150,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Semantics(
        label: 'Photo attachment. Tap to enlarge.',
        button: true,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(title: const Text('Photo')),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.memory(
                      snapshot.data!,
                      errorBuilder: (_, _, _) => const Text(
                        'Photo unavailable',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              snapshot.data!,
              width: 240,
              height: 180,
              fit: BoxFit.cover,
              cacheWidth: 720,
              errorBuilder: (_, _, _) => const SizedBox(
                width: 200,
                height: 120,
                child: Center(child: Text('Unsupported photo')),
              ),
            ),
          ),
        ),
      );
    },
  );
}
