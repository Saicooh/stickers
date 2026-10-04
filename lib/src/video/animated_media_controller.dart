import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'image_animation.dart';
import 'video_timeline.dart';

/// The same trim controls can play either a video or an image animation.
class AnimatedMediaController extends ValueNotifier<VideoPlayerValue> {
  final File file;
  VideoPlayerController? _video;
  ImageAnimation? animation;
  ui.Codec? _codec;
  ui.Image? _image;
  int _frame = -1;
  Timer? _timer;
  Timer? _positionTimer;
  final Stopwatch _playClock = Stopwatch();
  bool _loop = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  AnimatedMediaController(this.file) : super(VideoPlayerValue.uninitialized());

  Future<void> initialize() async {
    final imageAnimation = await ImageAnimation.isSupported(file);
    if (_disposed) return;
    if (imageAnimation) {
      final source = await ImageAnimation.load(file);
      if (_disposed) return;
      animation = source;
      value = value.copyWith(duration: source.duration, size: source.size, isInitialized: true);
      await seekTo(Duration.zero);
    } else {
      final video = VideoPlayerController.file(
        file,
        viewType: VideoViewType.textureView,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _video = video;
      video.addListener(() {
        if (!_disposed) value = video.value;
      });
      await video.setVolume(0);
      await video.setLooping(_loop);
      await video.initialize();
    }
  }

  Future<void> setLooping(bool loop) async {
    _loop = loop;
    await _video?.setLooping(loop);
  }

  Future<void> pause() async {
    _timer?.cancel();
    _positionTimer?.cancel();
    _playClock.stop();
    if (_video != null) return _video!.pause();
    if (!_disposed) value = value.copyWith(isPlaying: false);
  }

  Future<void> play() async {
    if (_video != null) return _video!.play();
    if (_disposed || animation == null) return;
    if (value.isCompleted) await seekTo(Duration.zero);
    if (_disposed) return;
    value = value.copyWith(isPlaying: true, isCompleted: false);
    _scheduleFrame();
    _trackPosition();
  }

  void _trackPosition() {
    _positionTimer?.cancel();
    if (_disposed || !value.isPlaying) return;
    final origin = value.position;
    _playClock
      ..reset()
      ..start();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (_disposed || !value.isPlaying) return;
      final position = origin + _playClock.elapsed;
      value = value.copyWith(position: position > value.duration ? value.duration : position);
    });
  }

  void _scheduleFrame() {
    _timer?.cancel();
    final source = animation!;
    final next = _frame + 1 < source.starts.length ? source.starts[_frame + 1] : source.duration;
    _timer = Timer(next - value.position, () async {
      if (_disposed || !value.isPlaying) return;
      try {
        if (next >= source.duration && !_loop) {
          _positionTimer?.cancel();
          _playClock.stop();
          value = value.copyWith(position: source.duration, isPlaying: false, isCompleted: true);
          return;
        }
        await seekTo(next >= source.duration ? Duration.zero : next);
        if (!_disposed && value.isPlaying) _scheduleFrame();
      } on Exception catch (error) {
        _positionTimer?.cancel();
        if (!_disposed) value = value.copyWith(isPlaying: false, errorDescription: error.toString());
      }
    });
  }

  Future<void> seekTo(Duration position) {
    if (_video != null) return _video!.seekTo(position);
    final operation = _pending.then((_) => _seekImage(position));
    // Keep later seeks usable even if an earlier decode failed.
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _seekImage(Duration position) async {
    final source = animation;
    if (_disposed || source == null) return;
    final target = source.frameAt(position);
    if (_codec == null || target < _frame) {
      _codec?.dispose();
      _codec = await source.codec(maxDimension: 1024);
      _frame = -1;
    }
    while (!_disposed && _frame < target) {
      final frame = await _codec!.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      _image?.dispose();
      _image = frame.image;
      _frame++;
    }
    if (!_disposed) {
      value = value.copyWith(position: position, isCompleted: false);
      if (value.isPlaying) {
        _scheduleFrame();
        _trackPosition();
      }
    }
  }

  Future<List<Uint8List?>> thumbnails() => animation?.thumbnails() ?? VideoTimelineService().thumbnails(file.path);

  Future<Duration> adjacentFrame(Duration position, int direction) async =>
      animation?.adjacentFrame(position, direction) ??
      await VideoTimelineService().adjacentFrame(file.path, position, direction);

  Widget preview() => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: this,
    builder: (context, value, _) =>
        _video != null ? VideoPlayer(_video!) : RawImage(image: _image, fit: BoxFit.contain),
  );

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _positionTimer?.cancel();
    _video?.dispose();
    _pending.whenComplete(() {
      _codec?.dispose();
      _image?.dispose();
    });
    super.dispose();
  }
}
