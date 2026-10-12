import 'dart:convert';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<void> saveReceiptFile(String name, Uint8List bytes) async {
  final link = web.HTMLAnchorElement()
    ..href = 'data:application/pdf;base64,${base64Encode(bytes)}'
    ..download = name;
  web.document.body?.append(link);
  link.click();
  link.remove();
}
