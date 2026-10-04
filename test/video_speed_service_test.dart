import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stickers/src/video/crop_scale.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('video trim sends speed separately from source trim and crop coordinates', () async {
    const methods = MethodChannel('de.loicezt.stickers/methods');
    const events = MethodChannel('de.loicezt.stickers/progress_trim');
    MethodCall? received;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methods, (call) async {
      received = call;
      return null;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    final service = CropAndScaleService();
    try {
      await service.start(
        inputFile: 'source.mp4',
        outputFile: 'output.mp4',
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 8),
        crop: const Rect.fromLTRB(.1, .2, .8, .9),
        stretch: false,
        quarterTurns: 1,
        speed: 1.7,
      );
      expect(received?.method, 'startTrim');
      expect(received?.arguments['speed'], 1.7);
      expect(received?.arguments['startTimeUs'], '2000000');
      expect(received?.arguments['endTimeUs'], '8000000');
      expect(received?.arguments['cropLeft'], .1);
      expect(received?.arguments['quarterTurns'], 1);
    } finally {
      service.dispose();
      await Future<void>.delayed(Duration.zero);
      messenger.setMockMethodCallHandler(methods, null);
      messenger.setMockMethodCallHandler(events, null);
    }
  });
}
