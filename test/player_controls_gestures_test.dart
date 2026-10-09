import 'package:duanju_app/player_controls.dart';
import 'package:duanju_app/player_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'player_fixtures.dart';

void main() {
  testWidgets(
    'landscape playback stays left and tools right, swipes hide chrome',
    (tester) async {
      tester.view.physicalSize = const Size(900, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = ScriptedPlayer();
      platform.state = platform.state.copyWith(
        playing: true,
        duration: const Duration(minutes: 2),
        position: const Duration(seconds: 30),
      );
      final player = Player(platformPlayer: platform);
      final interactions = PlayerInteractions(
        player: player,
        available: () => true,
        baseSpeed: () => 1,
        onTogglePlayback: () {},
        onFullscreen: () {},
        onEpisode: (_) => '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerControls(
              player: player,
              interactions: interactions,
              enabled: true,
              fullscreen: true,
              swipeEnabled: true,
              showOnPlaybackReady: true,
              onFullscreen: () {},
              onBack: () {},
              onPrevious: () {},
              onNext: () {},
              title: '合成播放',
              onTogglePlayback: () {},
              onEpisodes: () async {},
              onSpeed: () async {},
              onQuality: () async {},
              speed: 1,
              qualityLabel: '自动',
              onFocusSurface: () {},
              showDanmaku: true,
              onDanmaku: () async {},
            ),
          ),
        ),
      );
      final speed = tester.getRect(find.byKey(const ValueKey('player-speed')));
      final danmaku = tester.getRect(
        find.byKey(const ValueKey('player-danmaku-toggle')),
      );
      final progress = tester.getRect(
        find.byKey(const ValueKey('player-progress')),
      );
      expect(speed.bottom, closeTo(392, 1));
      expect(speed.top, greaterThanOrEqualTo(progress.bottom));
      expect(speed.left, greaterThan(450));
      final previous = tester.getRect(
        find.byKey(const ValueKey('player-bottom-previous')),
      );
      final playback = tester.getRect(
        find.byKey(const ValueKey('player-bottom-playback')),
      );
      final next = tester.getRect(
        find.byKey(const ValueKey('player-bottom-next')),
      );
      expect(previous.left, lessThan(40));
      expect(previous.top, greaterThanOrEqualTo(progress.bottom));
      expect(playback.left, greaterThan(previous.left));
      expect(next.left, greaterThan(playback.left));
      expect(next.right, lessThan(danmaku.left));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(playback.top, speed.top);
      expect(danmaku.top, speed.top);
      final overlay = find.descendant(
        of: find.byType(PlayerControls),
        matching: find.byType(AnimatedOpacity),
      );
      final drag = await tester.startGesture(const Offset(120, 200));
      await drag.moveBy(const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 0);
      expect(interactions.seekPreview, isNotNull);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 700));
      expect(player.state.position, greaterThan(const Duration(seconds: 30)));
      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 0);
      platform.state = platform.state.copyWith(buffering: true);
      platform.bufferingController.add(true);
      await tester.pump();
      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 0);
      await tester.tapAt(const Offset(120, 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<AnimatedOpacity>(overlay).opacity, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      interactions.dispose();
      await interactions.pendingRates;
      await interactions.pendingVolume;
      await player.dispose();
    },
  );
}
