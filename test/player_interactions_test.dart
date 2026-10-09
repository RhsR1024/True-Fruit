import 'package:duanju_app/playback_preferences.dart';
import 'package:duanju_app/player_interactions.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

class GestureHarness {
  GestureHarness({
    this.swipeEpisodes = true,
    Future<double> Function()? readVolume,
    Future<double> Function(double)? setVolume,
  }) {
    platform.state = platform.state.copyWith(
      position: const Duration(seconds: 60),
      duration: const Duration(seconds: 120),
      playing: true,
      volume: 50,
    );
    player = Player(platformPlayer: platform);
    interactions = PlayerInteractions(
      player: player,
      available: () => true,
      baseSpeed: () => 1,
      onTogglePlayback: () {},
      onFullscreen: () {},
      onEpisode: (direction) {
        episodes.add(direction);
        return '切集';
      },
      onSeek: (target) async {
        seeks.add(target);
      },
      swipeToChangeEpisode: () => swipeEpisodes,
      readGestureVolume: readVolume,
      onGestureVolume: setVolume,
      readBrightness: () async => brightness,
      onBrightness: (value) async {
        brightness = value;
      },
    );
  }

  final platform = ScriptedPlayer();
  late final Player player;
  late final PlayerInteractions interactions;
  bool swipeEpisodes;
  double brightness = .5;
  final episodes = <int>[];
  final seeks = <Duration>[];

  void down(
    Offset position, {
    int pointer = 1,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) {
    interactions.pointerDown(
      PointerDownEvent(
        pointer: pointer,
        position: position,
        kind: kind,
        buttons: kPrimaryButton,
      ),
      swipeEnabled: true,
      height: 400,
      width: 400,
    );
  }

  void move(Offset position) => interactions.pointerMove(
    PointerMoveEvent(
      pointer: 1,
      position: position,
      timeStamp: const Duration(milliseconds: 100),
    ),
  );

  void up() => interactions.pointerUp(
    const PointerUpEvent(pointer: 1, timeStamp: Duration(milliseconds: 200)),
  );

  Future<void> dispose() async {
    interactions.dispose();
    await interactions.pendingRates;
    await interactions.pendingVolume;
    await player.dispose();
  }
}

void main() {
  testWidgets('volume gestures read device volume and report applied steps', (
    tester,
  ) async {
    var deviceVolume = 20.0;
    final h = GestureHarness(
      swipeEpisodes: false,
      readVolume: () async => deviceVolume,
      setVolume: (value) async => deviceVolume = (value / 10).round() * 10.0,
    );
    addTearDown(h.dispose);
    h.down(const Offset(300, 200));
    h.move(const Offset(300, 100));
    h.up();
    await h.interactions.pendingVolume;
    expect(deviceVolume, 50);
    expect(h.interactions.feedback, '音量 50%');
    deviceVolume = 80;
    h.down(const Offset(300, 200));
    h.move(const Offset(300, 300));
    h.up();
    await h.interactions.pendingVolume;
    expect(deviceVolume, 60);
    expect(h.platform.state.volume, 50);
  });

  testWidgets('failed volume reads do not report a successful adjustment', (
    tester,
  ) async {
    var writes = 0;
    final h = GestureHarness(
      swipeEpisodes: false,
      readVolume: () async => throw StateError('unavailable'),
      setVolume: (value) async {
        writes++;
        return value;
      },
    );
    addTearDown(h.dispose);
    h.down(const Offset(300, 200));
    h.move(const Offset(300, 100));
    h.up();
    await h.interactions.pendingVolume;
    expect(writes, 0);
    expect(h.interactions.feedback, contains('音量调整失败'));
  });

  testWidgets('cancelled volume requests do not reach the device', (
    tester,
  ) async {
    var writes = 0;
    final h = GestureHarness(
      swipeEpisodes: false,
      readVolume: () async => 20,
      setVolume: (value) async {
        writes++;
        return value;
      },
    );
    addTearDown(h.dispose);
    h.down(const Offset(300, 200));
    h.move(const Offset(300, 100));
    h.interactions.pointerCancel(const PointerCancelEvent(pointer: 1));
    await h.interactions.pendingVolume;
    expect(writes, 0);
  });

  test('episode swipe defaults on and survives preference round trips', () {
    expect(PlaybackPreferences.fromJson({}).swipeToChangeEpisode, isTrue);
    final preferences = const PlaybackPreferences().copyWith(
      swipeToChangeEpisode: false,
    );
    final restored = PlaybackPreferences.fromJson(preferences.toJson());
    expect(restored.swipeToChangeEpisode, isFalse);
    expect(restored.copyWith(speed: 2).swipeToChangeEpisode, isFalse);
  });

  testWidgets('horizontal swipes preview, clamp, and seek only on release', (
    tester,
  ) async {
    final h = GestureHarness();
    addTearDown(h.dispose);
    h.down(const Offset(100, 200));
    h.move(const Offset(200, 205));
    expect(h.interactions.seekPreview, const Duration(seconds: 90));
    expect(h.seeks, isEmpty);
    h.up();
    expect(h.seeks, [const Duration(seconds: 90)]);
    expect(h.interactions.seekPreview, isNull);
    expect(h.interactions.suppressTap, isTrue);
    h.down(const Offset(300, 200));
    h.move(const Offset(-100, 200));
    h.up();
    expect(h.seeks.last, Duration.zero);
    h.down(const Offset(100, 200));
    h.move(const Offset(600, 200));
    h.up();
    expect(h.seeks.last, const Duration(seconds: 120));
    expect(h.episodes, isEmpty);
  });

  testWidgets('horizontal seeking also works with episode swipes disabled', (
    tester,
  ) async {
    final h = GestureHarness(swipeEpisodes: false);
    addTearDown(h.dispose);
    h.down(const Offset(300, 200));
    h.move(const Offset(200, 200));
    h.up();
    expect(h.seeks, [const Duration(seconds: 30)]);
    expect(h.episodes, isEmpty);
    expect(h.platform.state.volume, 50);
  });

  testWidgets('vertical swipes retain next and previous episode defaults', (
    tester,
  ) async {
    final h = GestureHarness();
    addTearDown(h.dispose);
    h.down(const Offset(100, 200));
    h.move(const Offset(100, 100));
    h.up();
    h.down(const Offset(300, 100));
    h.move(const Offset(300, 200));
    h.up();
    expect(h.episodes, [1, -1]);
    expect(h.seeks, isEmpty);
    expect(h.brightness, .5);
    expect(h.platform.state.volume, 50);
  });

  testWidgets(
    'disabled episode swipes adjust left brightness and right volume',
    (tester) async {
      final h = GestureHarness(swipeEpisodes: false);
      addTearDown(h.dispose);
      h.down(const Offset(100, 200));
      await tester.pump();
      h.move(const Offset(110, 100));
      h.up();
      expect(h.brightness, .75);
      h.down(const Offset(100, 200));
      await tester.pump();
      h.move(const Offset(110, 600));
      h.up();
      expect(h.brightness, .01);
      h.down(const Offset(300, 200));
      h.move(const Offset(300, 100));
      h.up();
      await h.interactions.pendingVolume;
      expect(h.platform.state.volume, 75);
      h.down(const Offset(300, 200));
      h.move(const Offset(300, 600));
      h.up();
      await h.interactions.pendingVolume;
      expect(h.platform.state.volume, 0);
      expect(h.episodes, isEmpty);
      expect(h.seeks, isEmpty);
    },
  );

  testWidgets('direction lock prevents a seek from switching episodes', (
    tester,
  ) async {
    final h = GestureHarness();
    addTearDown(h.dispose);
    h.down(const Offset(100, 200));
    h.move(const Offset(140, 202));
    h.move(const Offset(145, 350));
    h.up();
    expect(h.seeks, hasLength(1));
    expect(h.episodes, isEmpty);
  });

  testWidgets('multi-touch and pointer cancellation discard seek previews', (
    tester,
  ) async {
    final h = GestureHarness();
    addTearDown(h.dispose);
    h.down(const Offset(100, 200));
    h.move(const Offset(200, 200));
    h.down(const Offset(250, 200), pointer: 2);
    h.up();
    h.interactions.pointerUp(const PointerUpEvent(pointer: 2));
    expect(h.seeks, isEmpty);
    expect(h.interactions.seekPreview, isNull);
    h.down(const Offset(100, 200));
    h.move(const Offset(200, 200));
    h.interactions.pointerCancel(const PointerCancelEvent(pointer: 1));
    expect(h.seeks, isEmpty);
    expect(h.interactions.seekPreview, isNull);
  });

  testWidgets('long hold and mouse dragging do not turn into touch seeks', (
    tester,
  ) async {
    final h = GestureHarness();
    addTearDown(h.dispose);
    h.down(const Offset(100, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(h.interactions.boosting, isTrue);
    h.move(const Offset(300, 200));
    h.up();
    await h.interactions.pendingRates;
    expect(h.platform.state.rate, 1);
    h.down(const Offset(100, 200), kind: PointerDeviceKind.mouse);
    h.move(const Offset(300, 200));
    h.up();
    expect(h.seeks, isEmpty);
  });
}
