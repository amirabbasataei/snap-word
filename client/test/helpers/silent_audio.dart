import 'package:wordchain/core/services/audio_service.dart';

/// An [AudioOutput] that plays nothing, for tests that build a screen which
/// reads the [AudioService] (the profile's sound switches).
class SilentAudioOutput implements AudioOutput {
  @override
  Future<void> init() async {}
  @override
  void playSfx(Sound sound, double volume, double rate) {}
  @override
  Future<void> playMusic(MusicTrack track, double volume) async {}
  @override
  Future<void> pauseMusic() async {}
  @override
  Future<void> resumeMusic() async {}
  @override
  Future<void> stopMusic() async {}
}
