// lib/services/audio_service.dart
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// FIX: switched from remote freesound.org URLs (which 404'd) to LOCAL
// bundled assets. Filenames/extensions below match the actual files
// uploaded to assets/audio/ (mixed mp3/wav — audioplayers handles both
// natively, no conversion needed).
//
// FIX (carried over): init() must actually be called — it previously
// was defined but never invoked, so _players stayed empty forever and
// every play() call silently no-op'd.
//
// NOTE: 'invalid' and 'six' sound keys were removed since no asset files
// exist for them yet. Any code still calling _audio.play('invalid') or
// _audio.play('six') will just silently no-op (no crash) until real
// files are added later — at that point, add them back to _sfx below.
//
// NOTE: 'bgm' is left wired up but currently has no matching asset file
// (no bgm.mp3 was provided). It will silently fail to play (logged, not
// crashing) until a real background-music file is added at
// assets/audio/bgm.mp3 — no code changes will be needed at that point.
final audioServiceProvider = Provider((ref) {
  final svc = AudioService();
  svc.init();
  ref.onDispose(svc.dispose);
  return svc;
});

class AudioService {
  final Map<String, AudioPlayer> _players = {};
  bool sfxEnabled = true;
  bool bgmEnabled = true;

  // Paths are relative to the `assets/audio/` folder declared in
  // pubspec.yaml — AudioPlayer's AssetSource adds the `assets/` prefix
  // itself, so do NOT include it here.
  static const _sfx = {
    'dice':    'audio/dice.mp3',
    'move':    'audio/move.wav',
    'capture': 'audio/capture.wav',
    'win':     'audio/win.wav',
  };

  static const _bgmAsset = 'audio/bgm.mp3';

  // Loops only while it's the human player's turn in vsBot mode and
  // they haven't rolled yet — started/stopped by GameScreen based on
  // game state, not tied to screen lifecycle like bgm is.
  static const _waitingAsset = 'audio/waiting.wav';

  // FIX: each player is registered in _players BEFORE its setVolume call
  // is awaited, so the map is fully populated the instant init() runs
  // (no race where an early play()/startBgm() call finds the key missing).
  Future<void> init() async {
    for (final entry in _sfx.entries) {
      final p = AudioPlayer();
      _players[entry.key] = p;
      unawaited(p.setVolume(0.8));
    }

    final bgm = AudioPlayer();
    _players['bgm'] = bgm;
    unawaited(bgm.setVolume(0.25));
    unawaited(bgm.setReleaseMode(ReleaseMode.loop));

    final waiting = AudioPlayer();
    _players['waiting'] = waiting;
    unawaited(waiting.setVolume(0.35));
    unawaited(waiting.setReleaseMode(ReleaseMode.loop));
  }

  Future<void> play(String key) async {
    if (!sfxEnabled && key != 'bgm') return;
    try {
      final assetPath = _sfx[key];
      if (assetPath == null) return;
      final player = _players[key];
      if (player == null) {
        debugPrint('AudioService.play("$key"): no player registered yet');
        return;
      }
      await player.play(AssetSource(assetPath));
    } catch (e) {
      debugPrint('AudioService.play("$key") failed: $e');
    }
  }

  Future<void> startBgm() async {
    if (!bgmEnabled) return;
    try {
      final bgm = _players['bgm'];
      if (bgm == null) {
        debugPrint('AudioService.startBgm(): bgm player not registered yet');
        return;
      }
      await bgm.play(AssetSource(_bgmAsset));
    } catch (e) {
      debugPrint('AudioService.startBgm() failed: $e');
    }
  }

  Future<void> stopBgm() async {
    try {
      await _players['bgm']?.stop();
    } catch (e) {
      debugPrint('AudioService.stopBgm() failed: $e');
    }
  }

  // —— Waiting loop (vsBot: plays only during the human's own turn,
  // before they roll; stops the instant they roll or the turn ends) ——
  bool _waitingPlaying = false;

  Future<void> startWaiting() async {
    if (!bgmEnabled || _waitingPlaying) return;
    try {
      final w = _players['waiting'];
      if (w == null) {
        debugPrint('AudioService.startWaiting(): player not registered yet');
        return;
      }
      _waitingPlaying = true;
      await w.play(AssetSource(_waitingAsset));
    } catch (e) {
      _waitingPlaying = false;
      debugPrint('AudioService.startWaiting() failed: $e');
    }
  }

  Future<void> stopWaiting() async {
    if (!_waitingPlaying) return;
    try {
      _waitingPlaying = false;
      await _players['waiting']?.stop();
    } catch (e) {
      debugPrint('AudioService.stopWaiting() failed: $e');
    }
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
  }
}
