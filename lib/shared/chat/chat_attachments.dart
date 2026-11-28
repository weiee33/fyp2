import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../Customer/widgets/customer_dialogs.dart';
import '../localization/app_language.dart';

class ChatAttachment {
  ChatAttachment(this.bytes, this.id);
  final Uint8List bytes;
  final String id;
  String? uploadedPath;
}

const maxChatPhotos = 5;

Future<bool> photosFit(BuildContext context, int total) async {
  if (total <= maxChatPhotos) return true;
  await CustomerDialogs.show(
    context,
    message: tr('You can attach up to 5 photos per message.'),
  );
  return false;
}

Future<List<XFile>> pickChatPhotos(ImageSource source) async {
  final picker = ImagePicker();
  if (source == ImageSource.gallery) {
    return picker.pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
  }
  final photo = await picker.pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  return [if (photo != null) photo];
}

class ChatPhotoStrip extends StatelessWidget {
  const ChatPhotoStrip({
    super.key,
    required this.photos,
    required this.onRemove,
  });
  final List<ChatAttachment> photos;
  final ValueChanged<ChatAttachment>? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 72,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: photos.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, index) {
        final photo = photos[index];
        return Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                photo.bytes,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: tr('Remove photo'),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(32, 32),
                  padding: EdgeInsets.zero,
                ),
                onPressed: onRemove == null ? null : () => onRemove!(photo),
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ],
        );
      },
    ),
  );
}
