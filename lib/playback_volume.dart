import 'app_layout.dart';

class PlaybackVolume {
  static Future<double> read() async {
    final value = await AppDevice.channel.invokeMethod<double>(
      'getPlaybackVolume',
    );
    if (value == null || !value.isFinite) throw StateError('无法读取媒体音量');
    return value.clamp(0.0, 100.0);
  }

  static Future<double> set(double value) async {
    final actual = await AppDevice.channel.invokeMethod<double>(
      'setPlaybackVolume',
      {'value': value.clamp(0.0, 100.0)},
    );
    if (actual == null || !actual.isFinite) throw StateError('无法调整媒体音量');
    return actual.clamp(0.0, 100.0);
  }
}
