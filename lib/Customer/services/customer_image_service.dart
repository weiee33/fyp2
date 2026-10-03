import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Immutable objects are linked to a profile or booking by ownership-checked RPCs.
class CustomerImageService {
  static const maxBytes = 5 * 1024 * 1024;
  final SupabaseClient client;
  CustomerImageService(this.client);

  static String validate(Uint8List bytes, String extension) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Choose an image smaller than 5 MB.');
    }
    final ext = extension.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((match) => match);
    if ((ext == 'jpg' || ext == 'jpeg') && starts([0xff, 0xd8, 0xff]))
      return 'image/jpeg';
    if (ext == 'png' && starts([137, 80, 78, 71, 13, 10, 26, 10]))
      return 'image/png';
    if (ext == 'webp' &&
        bytes.length >= 12 &&
        starts([82, 73, 70, 70]) &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP')
      return 'image/webp';
    throw const FormatException('Choose a JPEG, PNG or WebP image.');
  }

  Future<String> upload({
    required String bucket,
    required String folder,
    required Uint8List bytes,
    required String extension,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null) throw const AuthException('Sign in to upload a photo.');
    final contentType = validate(bytes, extension);
    final suffix = contentType.split('/').last;
    final random = Random.secure();
    final name = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final path = '$uid/$folder/$name.$suffix';
    await client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }
}
