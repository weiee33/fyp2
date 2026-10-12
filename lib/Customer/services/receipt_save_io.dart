import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<void> saveReceiptFile(String name, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save payment receipt',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    bytes: bytes,
  );
  if (path != null && !Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
}
