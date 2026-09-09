import 'dart:io';
import 'dart:ui' show Rect;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the user the way the platform expects.
///
/// Desktop (Linux/Windows/macOS): prompts for a save location, writes [bytes]
/// there and returns the chosen path, or `null` if the user cancelled. Mobile:
/// opens the system share sheet and returns `null`.
///
/// Mirrors the flow already used for SGF downloads in local_board_page.dart and
/// my_games_page.dart.
Future<String?> saveOrShareFile({
  required String fileName,
  required List<int> bytes,
  required String mimeType,
  String? initialDirectory,
}) async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    final savePath = await FilePicker.platform.saveFile(
      fileName: fileName,
      initialDirectory: initialDirectory,
    );
    if (savePath == null) return null;
    await File(savePath).writeAsBytes(bytes);
    return savePath;
  }

  Rect? sharePositionOrigin;
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    final iosInfo = await DeviceInfoPlugin().iosInfo;
    if (iosInfo.model.toLowerCase().contains('ipad')) {
      // see https://github.com/fluttercommunity/plus_plugins/issues/3645
      sharePositionOrigin = const Rect.fromLTWH(0, 0, 1, 1);
    }
  }
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(Uint8List.fromList(bytes), mimeType: mimeType)],
    fileNameOverrides: [fileName],
    sharePositionOrigin: sharePositionOrigin,
  ));
  return null;
}
