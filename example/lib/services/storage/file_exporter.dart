import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class FileExporter {
  String _defaultName() {
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    return 'positioning_trace_$ts.jsonl';
  }

  Uint8List _toBytes(String jsonl) => Uint8List.fromList(utf8.encode(jsonl));

  /// Old behavior (app-private documents dir). Keep it for debugging.
  Future<String> writeJsonl(String jsonl) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${_defaultName()}');
    await file.writeAsString(jsonl);
    return file.path;
  }

  /// NEW: Save to user-selected location (Downloads / Drive / any provider).
  /// Returns a platform path/uri string (may not be a normal filesystem path on Android).
  Future<String?> saveJsonlAs(String jsonl, {String? fileName}) async {
    final name = fileName ?? _defaultName();
    final bytes = _toBytes(jsonl);

    final params = SaveFileDialogParams(
      data: bytes,
      fileName: name,
      // Optional: helps some pickers suggest apps/locations
      mimeTypesFilter: const ['application/json', 'text/plain'],
    );

    return FlutterFileDialog.saveFile(params: params);
  }

  /// NEW: Share the trace without needing filesystem access.
  Future<void> shareJsonl(
      String jsonl, {
        String? fileName,
        String? subject,
        String? text,
      }) async {
    final name = fileName ?? _defaultName();
    final bytes = _toBytes(jsonl);

    final xfile = XFile.fromData(
      bytes,
      name: name,
      mimeType: 'text/plain',
    );

    await Share.shareXFiles(
      [xfile],
      subject: subject ?? 'positioning_core trace',
      text: text ?? 'JSONL trace attached.',
    );
  }
}
