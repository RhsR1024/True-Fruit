import 'app_layout.dart';

class PlaybackBrightness {
  Future<void> _pending = Future<void>.value();
  int _revision = 0;
  bool _closed = false;
  bool _used = false;

  Future<double> read() async {
    await _pending;
    if (_closed) throw StateError('播放器已关闭');
    final value = await AppDevice.channel.invokeMethod<double>(
      'getPlaybackBrightness',
    );
    if (value == null || !value.isFinite) throw StateError('无法读取亮度');
    return value.clamp(.01, 1.0);
  }

  Future<void> set(double value) {
    if (_closed) return Future<void>.value();
    _used = true;
    final revision = _revision;
    final next = _pending.then((_) async {
      if (_closed || revision != _revision) return;
      await AppDevice.channel.invokeMethod<void>('setPlaybackBrightness', {
        'value': value.clamp(.01, 1.0),
      });
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  void reset() {
    _revision++;
    if (!_used) return;
    _used = false;
    _pending = _pending
        .then((_) async {
          await AppDevice.channel.invokeMethod<void>('resetPlaybackBrightness');
        })
        .catchError((Object _) {});
  }

  void dispose() {
    _closed = true;
    reset();
  }
}
