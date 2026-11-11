import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wordchain/core/services/audio_service.dart';

class FakeOutput implements AudioOutput {
  final log = <String>[];

  /// When set, [init] does not finish until it completes.
  Completer<void>? initGate;

  @override
  Future<void> init() async => initGate?.future;
  @override
  void playSfx(Sound sound, double volume, double rate) =>
      log.add('sfx:${sound.file}@$rate');
  @override
  Future<void> playMusic(MusicTrack track, double volume) async =>
      log.add('play:${track.file}');
  @override
  Future<void> pauseMusic() async => log.add('pause');
  @override
  Future<void> resumeMusic() async => log.add('resume');
  @override
  Future<void> stopMusic() async => log.add('stop');
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeOutput out;
  late SharedPreferences prefs;
  late AudioService audio;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    out = FakeOutput();
    audio = AudioService(prefs: prefs, output: out);
    await audio.init();
  });

  test('both switches default to on and are remembered', () async {
    expect(audio.sfxOn.value, isTrue);
    expect(audio.musicOn.value, isTrue);
    await audio.setSfxEnabled(false);
    await audio.setMusicEnabled(false);
    final again = AudioService(prefs: prefs, output: FakeOutput());
    expect(again.sfxOn.value, isFalse);
    expect(again.musicOn.value, isFalse);
  });

  test('effects play only while the switch is on', () async {
    audio.play(Sound.accepted);
    await audio.setSfxEnabled(false);
    audio.play(Sound.rejected);
    expect(out.log, ['sfx:accepted@1.0']);
  });

  test('the same effect twice within a few ms plays once', () {
    audio.play(Sound.tap);
    audio.play(Sound.tap);
    expect(out.log, ['sfx:tap@1.0']);
  });

  test('keyboard sounds are never debounced: fast typing plays every press', () {
    audio.play(Sound.key, rate: KeyPitch.rateFor(1));
    audio.play(Sound.key, rate: KeyPitch.rateFor(1));
    audio.play(Sound.keyBack);
    audio.play(Sound.keyBack);
    audio.play(Sound.keySend);
    audio.play(Sound.keySend);
    expect(out.log.length, 6);
  });

  test('a sound asked for before init finished plays when it did', () async {
    final gate = Completer<void>();
    final slow = FakeOutput()..initGate = gate;
    final early = AudioService(prefs: prefs, output: slow);
    final init = early.init();
    early.play(Sound.keySend);
    expect(slow.log, isEmpty);
    gate.complete();
    await init;
    expect(slow.log, ['sfx:key_send@1.0']);
  });

  test('a failed init drops sounds quietly and never throws', () async {
    final broken = _BrokenOutput();
    final dead = AudioService(prefs: prefs, output: broken);
    await dead.init();
    expect(() => dead.play(Sound.tap), returnsNormally);
    expect(broken.played, 0);
  });

  test('key pitch: one voice per step, stable per letter', () {
    expect(Sound.key.voices, KeyPitch.steps);
    for (var i = 0; i < KeyPitch.steps; i++) {
      expect(pickVoice(Sound.key, KeyPitch.rateFor(i), 99), i);
    }
    expect(KeyPitch.rateFor(KeyPitch.steps + 2), KeyPitch.rateFor(2));
    expect(KeyPitch.rateFor(-1), KeyPitch.rateFor(KeyPitch.steps - 1));
  });

  test('other sounds rotate through their voices', () {
    expect([for (var i = 0; i < 5; i++) pickVoice(Sound.tick, 1.0, i)], [0, 1, 0, 1, 0]);
    expect(pickVoice(Sound.keySend, 1.0, 7), 0);
  });

  test('music follows the requested track and does not restart', () async {
    audio.setMusic(MusicTrack.menu);
    await settle();
    audio.setMusic(MusicTrack.menu);
    await settle();
    audio.setMusic(MusicTrack.game);
    await settle();
    audio.setMusic(null);
    await settle();
    expect(out.log, ['play:menu', 'play:game', 'stop']);
  });

  test('switching music off stops it and on starts the wanted loop again', () async {
    audio.setMusic(MusicTrack.menu);
    await settle();
    await audio.setMusicEnabled(false);
    await settle();
    expect(audio.playingTrack, isNull);
    await audio.setMusicEnabled(true);
    await settle();
    expect(out.log, ['play:menu', 'stop', 'play:menu']);
  });

  test('the background pauses, the return resumes the same loop', () async {
    audio.setMusic(MusicTrack.game);
    await settle();
    audio.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    audio.play(Sound.accepted); // silent while backgrounded
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(out.log, ['play:game', 'pause', 'resume']);
  });

  test('a scene change while backgrounded starts only on return', () async {
    audio.setMusic(MusicTrack.menu);
    await settle();
    audio.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    audio.setMusic(MusicTrack.game);
    await settle();
    audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(out.log, ['play:menu', 'pause', 'play:game']);
  });

  test('every sound and track has its asset file', () {
    for (final s in Sound.values) {
      expect(File('assets/${s.asset}').existsSync(), isTrue, reason: s.asset);
    }
    for (final t in MusicTrack.values) {
      expect(File('assets/${t.asset}').existsSync(), isTrue, reason: t.asset);
    }
  });

  test('Sfx is a no-op when no service is registered', () {
    expect(() => Sfx.play(Sound.tap), returnsNormally);
    expect(() => Sfx.music(MusicTrack.menu), returnsNormally);
  });
}

class _BrokenOutput extends FakeOutput {
  int played = 0;
  @override
  Future<void> init() async => throw StateError('no audio engine');
  @override
  void playSfx(Sound sound, double volume, double rate) => played++;
}
