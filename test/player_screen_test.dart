import 'package:duanju_app/local_store.dart';
import 'package:duanju_app/models.dart';
import 'package:duanju_app/player_screen.dart';
import 'package:duanju_app/player_controls.dart';
import 'package:duanju_app/app_theme.dart';
import 'package:duanju_app/app_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'player_fixtures.dart';

void main() {
  Future<void> settleOperations(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> mount(
    WidgetTester tester,
    RouteRepository repository,
    ScriptedPlayer platform, {
    Size? size,
    FakeViewPadding? padding,
    ThemeData? theme,
  }) async {
    SharedPreferences.setMockInitialValues({});
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
    }
    if (padding != null) {
      tester.view.padding = padding;
    }
    final store = LocalStore(await SharedPreferences.getInstance());
    final detail = await repository.detail(FixtureRepository.free);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? ThemeData.dark(),
        home: PlayerScreen(
          detail: detail,
          initialIndex: 0,
          initialPosition: 7,
          repository: repository,
          store: store,
          playerFactory: () => Player(platformPlayer: platform),
          videoBuilder: (controls) => controls,
        ),
      ),
    );
    await settleOperations(tester);
  }

  Future<void> unmount(WidgetTester tester, ScriptedPlayer player) async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    await settleOperations(tester);
    expect(player.disposed, isTrue);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'duplicate errors switch once while keeping progress, rate and pause state',
    (tester) async {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      await tester.tap(find.byKey(const ValueKey('player-speed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5x').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭菜单'));
      await tester.pumpAndSettle();
      await player.seek(const Duration(seconds: 28));
      await tester.pump();
      await tester.tap(find.byTooltip('暂停播放'));
      await settleOperations(tester);
      player.fail();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleOperations(tester);
      expect(repository.fallbackCalls, 1);
      expect(repository.primaryCalls, 1);
      expect(player.opened.last.start, const Duration(seconds: 28));
      expect(player.state.rate, 1.5);
      expect(player.played.last, isFalse);
      expect(repository.active.length, 1);
      expect(find.text('暂时无法播放'), findsNothing);
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets(
    'recovery exhaustion releases sessions and manual retry keeps the saved position',
    (tester) async {
      final repository = RouteRepository()..broken = true;
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
        await settleOperations(tester);
      }
      expect(repository.primaryCalls, 2);
      expect(repository.fallbackCalls, 2);
      expect(find.text('暂时无法播放'), findsOneWidget);
      expect(repository.active, isEmpty);
      await tester.pump(const Duration(seconds: 25));
      expect(repository.primaryCalls + repository.fallbackCalls, 4);
      repository.broken = false;
      await tester.tap(find.text('重试播放'));
      await settleOperations(tester);
      expect(player.opened.last.start, const Duration(seconds: 7));
      expect(find.text('暂时无法播放'), findsNothing);
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets(
    'switching episodes ignores a delayed fallback and frees both old plans',
    (tester) async {
      final repository = RouteRepository()..deferFallback = true;
      final player = ScriptedPlayer();
      await mount(tester, repository, player);
      player.fail();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await settleOperations(tester);
      expect(repository.pending, isNotNull);
      await tester.tap(find.byKey(const ValueKey('play-episode-2')));
      await settleOperations(tester);
      final currentURL = player.opened.last.uri;
      final late = PlaybackPlan(
        url: 'https://media.test/late.mp4',
        session: 'late',
      );
      repository.active.add(late.session);
      repository.pending!.complete(late);
      await settleOperations(tester);
      expect(player.opened.last.uri, currentURL);
      expect(repository.active.length, 1);
      expect(repository.active, isNot(contains('late')));
      await unmount(tester, player);
      expect(repository.active, isEmpty);
    },
  );

  testWidgets('picture-in-picture hides app overlay controls', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
      switch (call.method) {
        case 'pictureInPictureStatus':
          return {'supported': true, 'active': false};
        case 'enterPictureInPicture':
          return {'supported': true, 'active': true, 'requested': true};
      }
      return null;
    });
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      expect(
        find.byKey(const ValueKey('player-picture-in-picture')),
        findsOneWidget,
      );
      expect(find.text('选集'), findsOneWidget);
      expect(find.text('简介'), findsOneWidget);
      expect(find.text('下载'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('player-picture-in-picture')));
      await tester.pump();
      await tester.pump();
      await settleOperations(tester);
      expect(
        find.byKey(const ValueKey('player-picture-in-picture')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('player-speed')), findsNothing);
      expect(find.byKey(const ValueKey('player-quality')), findsNothing);
      expect(find.byKey(const ValueKey('player-progress')), findsNothing);
      expect(find.text('选集'), findsNothing);
      expect(find.text('简介'), findsNothing);
      expect(find.text('下载'), findsNothing);
      await unmount(tester, player);
    } finally {
      messenger.setMockMethodCallHandler(AppDevice.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile player pane starts below the system status area', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(
        tester,
        repository,
        player,
        size: const Size(390, 844),
        padding: const FakeViewPadding(top: 32),
      );
      final surface = tester.getRect(
        find.byKey(const ValueKey('player-gesture-surface')),
      );
      expect(surface.top, greaterThanOrEqualTo(32));
      await unmount(tester, player);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPadding();
    }
  });

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('surface taps only toggle controls at $size', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: size);
      player.videoSize(320, 180);
      await settleOperations(tester);
      if (size.width > size.height) {
        expect(
          tester.widget<PlayerControls>(find.byType(PlayerControls)).fullscreen,
          isTrue,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('player-speed'))).top,
          greaterThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('player-progress')))
                .bottom,
          ),
        );
      }
      final surface = tester.getRect(
        find.byKey(const ValueKey('player-gesture-surface')),
      );
      final points = [
        Offset(
          surface.left + surface.width * .15,
          surface.top + surface.height * .35,
        ),
        Offset(
          surface.left + surface.width * .85,
          surface.top + surface.height * .35,
        ),
      ];
      final overlay = find.descendant(
        of: find.byType(PlayerControls),
        matching: find.byType(AnimatedOpacity),
      );
      expect(player.state.playing, isTrue);
      for (final point in points) {
        final opacity = tester.widget<AnimatedOpacity>(overlay).opacity;
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 400));
        expect(player.state.playing, isTrue);
        expect(tester.widget<AnimatedOpacity>(overlay).opacity, 1 - opacity);
      }
      for (var i = 0; i < points.length; i++) {
        await tester.tapAt(points[i]);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(points[i]);
        await tester.pump(const Duration(milliseconds: 400));
        expect(player.state.playing, i == 1);
      }
      await tester.tap(find.byTooltip('暂停播放'));
      await settleOperations(tester);
      expect(player.state.playing, isFalse);
      await tester.tapAt(points.first);
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.state.playing, isFalse);
      await tester.tap(find.byTooltip('开始播放'));
      await settleOperations(tester);
      expect(player.state.playing, isTrue);
      await unmount(tester, player);
    });
  }

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets('video text and controls stay white in ${theme.brightness}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(
        tester,
        repository,
        player,
        size: const Size(844, 390),
        theme: theme,
      );
      player.videoSize(320, 180);
      await settleOperations(tester);
      final controls = tester.widget<PlayerControls>(
        find.byType(PlayerControls),
      );
      expect(controls.fullscreen, isTrue);
      Color? textColor(Finder finder) => tester
          .widget<RichText>(
            find.descendant(of: finder, matching: find.byType(RichText)),
          )
          .text
          .style
          ?.color;
      expect(textColor(find.text(controls.title)), Colors.white);
      expect(textColor(find.text('1.0x')), Colors.white);
      expect(textColor(find.text('自动')), Colors.white);
      expect(textColor(find.text('弹')), Colors.white);
      for (final icon in [
        Icons.arrow_back_rounded,
        Icons.pause_rounded,
        Icons.skip_next_rounded,
      ]) {
        expect(
          IconTheme.of(tester.element(find.byIcon(icon))).color,
          Colors.white,
        );
      }
      expect(
        IconTheme.of(
          tester.element(find.byIcon(Icons.skip_previous_rounded)),
        ).color,
        Colors.white54,
      );
      final surface = tester.getRect(
        find.byKey(const ValueKey('player-gesture-surface')),
      );
      final gesture = await tester.startGesture(
        Offset(
          surface.left + surface.width * .15,
          surface.top + surface.height * .35,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.state.rate, 3);
      expect(textColor(find.text('3 倍速 · 松开恢复')), Colors.white);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(player.state.rate, 1);
      expect(player.state.playing, isTrue);
      expect(textColor(find.text('恢复 1.0 倍速')), Colors.white);
      await unmount(tester, player);
    });
  }

  testWidgets('compact player tools stay clustered instead of evenly spread', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppDevice.channel, (call) async {
      if (call.method == 'pictureInPictureStatus') {
        return {'supported': true, 'active': false};
      }
      return null;
    });
    try {
      final repository = RouteRepository();
      final player = ScriptedPlayer();
      await mount(tester, repository, player, size: const Size(390, 844));
      final speed = tester.getRect(find.byKey(const ValueKey('player-speed')));
      final quality = tester.getRect(
        find.byKey(const ValueKey('player-quality')),
      );
      final pip = tester.getRect(
        find.byKey(const ValueKey('player-picture-in-picture')),
      );
      expect(quality.left - speed.right, lessThan(8));
      expect(pip.left - quality.right, lessThan(8));
      expect(pip.right, greaterThan(330));
      await unmount(tester, player);
    } finally {
      messenger.setMockMethodCallHandler(AppDevice.channel, null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
