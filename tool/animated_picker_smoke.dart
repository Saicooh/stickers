// flutter run -t tool/animated_picker_smoke.dart --dart-define=PICKER_SOURCE=gif
// Set PICKER_SOURCE=video to check the video-only gallery instead. No packs are opened or modified.
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:stickers/src/video/animated_media_picker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;
  const sourceName = String.fromEnvironment('PICKER_SOURCE', defaultValue: 'gif');
  final source = sourceName == 'video' ? AnimatedMediaSource.video : AnimatedMediaSource.gif;
  final status = ValueNotifier('Opening $sourceName gallery…');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: ValueListenableBuilder(
            valueListenable: status,
            builder: (context, value, _) => Text(value),
          ),
        ),
      ),
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final path = await AnimatedMediaPicker().pick(source);
      status.value = path == null ? 'PICKER_CANCELLED' : 'PICKER_ACCEPTED: $sourceName';
    } catch (error) {
      status.value = 'PICKER_REJECTED: $error';
    }
    debugPrint(status.value);
  });
}
