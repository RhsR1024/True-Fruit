import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'widgets.dart';

enum _TouchGesture { none, seek, episode, brightness, volume }

class PlayerInteractions extends ChangeNotifier {
  PlayerInteractions({
    required this.player,
    required this.available,
    required this.baseSpeed,
    required this.onTogglePlayback,
    required this.onFullscreen,
    required this.onEpisode,
    this.onSeek,
    this.swipeToChangeEpisode,
    this.readBrightness,
    this.onBrightness,
    this.readGestureVolume,
    this.onGestureVolume,
  }) {
    _playing = player.stream.playing.listen((playing) {
      if (!playing) cancel();
    });
  }

  final Player player;
  final bool Function() available;
  final double Function() baseSpeed;
  final VoidCallback onTogglePlayback;
  final VoidCallback onFullscreen;
  final String Function(int direction) onEpisode;
  final Future<void> Function(Duration)? onSeek;
  final bool Function()? swipeToChangeEpisode;
  final Future<double> Function()? readBrightness;
  final Future<void> Function(double)? onBrightness;
  final Future<double> Function()? readGestureVolume;
  final Future<double> Function(double)? onGestureVolume;
  late final StreamSubscription<bool> _playing;
  Timer? _holdTimer;
  Timer? _hintTimer;
  Future<void> _rates = Future<void>.value();
  final Set<int> _pointers = {};
  int? _pointer;
  Offset? _origin;
  Offset? _lastPosition;
  Duration _started = Duration.zero;
  double _swipeThreshold = 70;
  bool _swipeEnabled = false;
  bool _touchEnabled = false;
  bool _episodeSwipeEnabled = true;
  double _gestureWidth = 1;
  double _gestureHeight = 1;
  Future<double?>? _initialVolume;
  int _volumeRequest = 0;
  double? _initialBrightness;
  bool _brightnessUnavailable = false;
  Duration _initialPosition = Duration.zero;
  Duration _gestureDuration = Duration.zero;
  Duration? _seekPreview;
  int _gestureRevision = 0;
  _TouchGesture _gesture = _TouchGesture.none;
  Future<void> _volumes = Future<void>.value();
  bool _moved = false;
  bool _held = false;
  bool _boosting = false;
  bool _keyboardHold = false;
  bool _cancelUntilRelease = false;
  bool _disposed = false;
  double _unmutedVolume = 100;
  String _feedback = '';
  DateTime _ignoreTapUntil = DateTime(2000);

  String get feedback => _feedback;
  bool get boosting => _boosting;
  bool get suppressTap => DateTime.now().isBefore(_ignoreTapUntil);
  Future<void> get pendingRates => _rates;
  Future<void> get pendingVolume => _volumes;
  Duration? get seekPreview => _seekPreview;
  bool get gesturing => _gesture != _TouchGesture.none;

  void hint(String message, {bool persistent = false}) {
    if (_disposed) return;
    _hintTimer?.cancel();
    if (_feedback != message) {
      _feedback = message;
      notifyListeners();
    }
    if (!persistent && message.isNotEmpty) {
      _hintTimer = Timer(const Duration(milliseconds: 1200), () {
        hint(_boosting ? '3 倍速 · 松开恢复' : '', persistent: true);
      });
    }
  }

  Future<void> applySpeed() => _setRate(baseSpeed());

  Future<void> _setRate(double value) {
    _rates = _rates
        .catchError((Object _) {})
        .then((_) => player.setRate(value));
    unawaited(
      _rates.catchError((Object _) {
        hint('倍速调整失败，请重试');
      }),
    );
    return _rates;
  }

  void _beginHold({bool keyboard = false}) {
    if (!available() || _holdTimer != null || _boosting) return;
    _keyboardHold = keyboard;
    _holdTimer = Timer(const Duration(milliseconds: 350), () {
      _holdTimer = null;
      if (_disposed ||
          !available() ||
          !player.state.playing ||
          player.state.completed) {
        return;
      }
      _boosting = true;
      _held = true;
      unawaited(_setRate(3));
      hint('3 倍速 · 松开恢复', persistent: true);
    });
  }

  void _endHold({bool tap = false, bool silent = false}) {
    final wasKeyboard = _keyboardHold;
    final boosted = _boosting;
    _holdTimer?.cancel();
    _holdTimer = null;
    _keyboardHold = false;
    _boosting = false;
    if (boosted) {
      unawaited(_setRate(baseSpeed()));
      if (!silent) hint('恢复 ${baseSpeed()} 倍速');
    } else if (tap && wasKeyboard) {
      seek(5);
    }
  }

  void cancel() {
    if (_disposed) return;
    if (_pointers.isNotEmpty) {
      _cancelUntilRelease = true;
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    _gestureRevision++;
    _volumeRequest++;
    _gesture = _TouchGesture.none;
    _seekPreview = null;
    _pointer = null;
    _origin = null;
    _lastPosition = null;
    _endHold(silent: true);
    hint('');
  }

  void pointerDown(
    PointerDownEvent event, {
    required bool swipeEnabled,
    required double height,
    required double width,
  }) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1 || _cancelUntilRelease) {
      cancel();
      return;
    }
    if (!available() || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _origin = _lastPosition = event.localPosition;
    _started = event.timeStamp;
    _touchEnabled = event.kind == PointerDeviceKind.touch;
    _swipeEnabled = swipeEnabled && _touchEnabled;
    _episodeSwipeEnabled = swipeToChangeEpisode?.call() ?? true;
    _gestureWidth = math.max(1, width);
    _gestureHeight = math.max(1, height);
    _swipeThreshold = math.max(56, math.min(100, height * .1));
    _gesture = _TouchGesture.none;
    _seekPreview = null;
    _initialPosition = player.state.position;
    _gestureDuration = player.state.duration;
    _initialVolume = null;
    _initialBrightness = null;
    _brightnessUnavailable = readBrightness == null || onBrightness == null;
    final revision = ++_gestureRevision;
    if (_swipeEnabled &&
        !_episodeSwipeEnabled &&
        event.localPosition.dx < _gestureWidth / 2) {
      unawaited(_loadBrightness(revision));
    }
    if (_swipeEnabled &&
        !_episodeSwipeEnabled &&
        event.localPosition.dx >= _gestureWidth / 2) {
      _initialVolume = _readVolume();
    }
    _moved = _held = false;
    _beginHold();
  }

  Future<void> _loadBrightness(int revision) async {
    try {
      final brightness = await readBrightness?.call();
      if (_disposed || revision != _gestureRevision || !available()) return;
      _initialBrightness = brightness;
      if (_gesture == _TouchGesture.brightness) _updateBrightness();
    } catch (_) {
      if (!_disposed && revision == _gestureRevision) {
        _brightnessUnavailable = true;
        if (_gesture == _TouchGesture.brightness) _updateBrightness();
      }
    }
  }

  void pointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer || _origin == null) return;
    if (!available()) {
      cancel();
      return;
    }
    _lastPosition = event.localPosition;
    final delta = event.localPosition - _origin!;
    if (delta.distance <= 12 && !_moved) return;
    _moved = true;
    _endHold();
    if (!_touchEnabled || _held) return;
    if (_gesture == _TouchGesture.none) {
      if (delta.dx.abs() > delta.dy.abs() * 1.2) {
        _gesture = _TouchGesture.seek;
      } else if (_swipeEnabled && delta.dy.abs() > delta.dx.abs() * 1.2) {
        _gesture = _episodeSwipeEnabled
            ? _TouchGesture.episode
            : _origin!.dx < _gestureWidth / 2
            ? _TouchGesture.brightness
            : _TouchGesture.volume;
      }
      if (gesturing) notifyListeners();
    }
    switch (_gesture) {
      case _TouchGesture.seek:
        if (_gestureDuration <= Duration.zero) {
          hint('当前视频暂不支持调整进度');
          return;
        }
        final span = math.min(_gestureDuration.inMilliseconds, 120000);
        final target =
            (_initialPosition.inMilliseconds + delta.dx / _gestureWidth * span)
                .round()
                .clamp(0, _gestureDuration.inMilliseconds);
        _seekPreview = Duration(milliseconds: target);
        hint(
          '跳转至 ${formatPosition(target / 1000)} / '
          '${formatPosition(_gestureDuration.inMilliseconds / 1000)} · 松开跳转',
          persistent: true,
        );
        notifyListeners();
      case _TouchGesture.volume:
        _setGestureVolume(-delta.dy / _gestureHeight * 100);
      case _TouchGesture.brightness:
        _updateBrightness();
      case _TouchGesture.episode:
      case _TouchGesture.none:
        break;
    }
  }

  void _updateBrightness() {
    if (_brightnessUnavailable) {
      hint('当前设备无法调节亮度');
      return;
    }
    if (_initialBrightness == null ||
        onBrightness == null ||
        _origin == null ||
        _lastPosition == null)
      return;
    final brightness =
        (_initialBrightness! -
                (_lastPosition!.dy - _origin!.dy) / _gestureHeight)
            .clamp(.01, 1.0);
    final revision = _gestureRevision;
    hint('亮度 ${(brightness * 100).round()}%', persistent: true);
    unawaited(
      onBrightness!(brightness).catchError((Object _) {
        if (!_disposed && revision == _gestureRevision) hint('亮度调整失败，请重试');
      }),
    );
  }

  void pointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_cancelUntilRelease) {
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
      if (_pointers.isEmpty) _cancelUntilRelease = false;
      return;
    }
    if (_pointer != event.pointer || _origin == null) return;
    final delta = (_lastPosition ?? event.localPosition) - _origin!;
    final swipe =
        _gesture == _TouchGesture.episode &&
        !_held &&
        delta.dy.abs() >= _swipeThreshold &&
        delta.dy.abs() > delta.dx.abs() * 1.5 &&
        event.timeStamp - _started < const Duration(milliseconds: 1500);
    final target = _gesture == _TouchGesture.seek ? _seekPreview : null;
    if (_moved || _held) {
      _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    }
    _gestureRevision++;
    _gesture = _TouchGesture.none;
    _seekPreview = null;
    _pointer = null;
    _origin = null;
    _lastPosition = null;
    _endHold();
    if (available()) {
      if (target != null) {
        unawaited(_commitSeek(target));
        hint('跳转至 ${formatPosition(target.inMilliseconds / 1000)}');
      } else if (swipe) {
        hint(onEpisode(delta.dy < 0 ? 1 : -1));
      } else {
        hint(_feedback);
      }
    }
    notifyListeners();
  }

  Future<void> _commitSeek(Duration target) async {
    try {
      await (onSeek ?? player.seek)(target);
    } catch (_) {
      hint('跳转失败，请重试');
    }
  }

  void pointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    cancel();
    _ignoreTapUntil = DateTime.now().add(const Duration(milliseconds: 600));
    if (_pointers.isEmpty) _cancelUntilRelease = false;
  }

  void _setVolume(double volume) {
    if (volume > 0) _unmutedVolume = volume;
    _volumes = _volumes.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      try {
        await player.setVolume(volume);
      } catch (_) {
        hint('音量调整失败，请重试');
      }
    });
    hint(volume == 0 ? '已静音' : '音量 ${volume.round()}%');
  }

  Future<double?> _readVolume() async {
    try {
      await _volumes;
      final volume =
          await (readGestureVolume?.call() ??
              Future.value(player.state.volume));
      if (!volume.isFinite) return null;
      return volume.clamp(0.0, 100.0);
    } catch (_) {
      return null;
    }
  }

  void _setGestureVolume(double delta) {
    final initial = _initialVolume;
    final request = ++_volumeRequest;
    _volumes = _volumes.catchError((Object _) {}).then((_) async {
      try {
        final start = await initial;
        if (_disposed || !available() || request != _volumeRequest) return;
        if (start == null) throw StateError('无法读取音量');
        final target = (start + delta).clamp(0.0, 100.0);
        final double actual;
        if (onGestureVolume != null) {
          actual = await onGestureVolume!(target);
        } else {
          await player.setVolume(target);
          actual = target;
          if (actual > 0) _unmutedVolume = actual;
        }
        if (_disposed || request != _volumeRequest) return;
        hint(actual == 0 ? '已静音' : '音量 ${actual.round()}%');
      } catch (_) {
        if (!_disposed && request == _volumeRequest) {
          hint('音量调整失败，请检查设备媒体音量');
        }
      }
    });
  }

  void seek(int seconds) {
    if (!available() || player.state.duration <= Duration.zero) return;
    _endHold();
    final target = (player.state.position.inMilliseconds + seconds * 1000)
        .clamp(0, player.state.duration.inMilliseconds);
    unawaited(_commitSeek(Duration(milliseconds: target)));
    hint('${seconds > 0 ? '快进至' : '后退至'} ${formatPosition(target / 1000)}');
  }

  void changeVolume(double delta) {
    if (!available()) return;
    final volume = (player.state.volume + delta).clamp(0.0, 100.0);
    _setVolume(volume);
  }

  void toggleMute() {
    if (!available()) return;
    final current = player.state.volume;
    if (current > 0) _unmutedVolume = current;
    final target = current > 0 ? 0.0 : _unmutedVolume;
    _setVolume(target);
  }

  KeyEventResult key(KeyEvent event) {
    final key = event.logicalKey;
    if (event is KeyUpEvent) {
      if (key == LogicalKeyboardKey.arrowRight && _keyboardHold) {
        _endHold(tap: available());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final hardware = HardwareKeyboard.instance;
    if (hardware.isAltPressed ||
        hardware.isMetaPressed ||
        hardware.isShiftPressed) {
      cancel();
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.keyF) {
      if (event is KeyDownEvent) {
        cancel();
        onFullscreen();
      }
      return KeyEventResult.handled;
    }
    if (hardware.isControlPressed || !available()) {
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.arrowRight) _endHold();
    if (key == LogicalKeyboardKey.arrowRight) {
      if (event is KeyDownEvent) _beginHold(keyboard: true);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      seek(-5);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      changeVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      changeVolume(-5);
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      if (event is KeyDownEvent) onTogglePlayback();
    } else if (key == LogicalKeyboardKey.keyM) {
      if (event is KeyDownEvent) toggleMute();
    } else if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (event is KeyDownEvent) {
        hint(onEpisode(key == LogicalKeyboardKey.mediaTrackNext ? 1 : -1));
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _disposed = true;
    _holdTimer?.cancel();
    _hintTimer?.cancel();
    if (_boosting) unawaited(_setRate(baseSpeed()));
    _boosting = false;
    _playing.cancel();
    _pointers.clear();
    super.dispose();
  }
}
