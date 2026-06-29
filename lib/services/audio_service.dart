// lib/services/audio_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioServiceProvider = Provider((ref) {
  final svc = AudioService();
  ref.onDispose(svc.dispose);
  return svc;
});

class AudioService {
  final Map<String, AudioPlayer> _players = {};
  bool sfxEnabled = true;
  bool bgmEnabled = true;

  static const _sfx = {
    'dice':    'https://cdn.freesound.org/previews/362/362204_1676145-lq.mp3',
    'move':    'https://cdn.freesound.org/previews/399/399934_1676145-lq.mp3',
    'capture': 'https://cdn.freesound.org/previews/331/331912_3248244-lq.mp3',
    'win':     'https://cdn.freesound.org/previews/456/456966_9159316-lq.mp3',
    'invalid': 'https://cdn.freesound.org/previews/142/142608_1840739-lq.mp3',
    'six':     'https://cdn.freesound.org/previews/270/270402_5123851-lq.mp3',
  };

  static const _bgmUrl = 'https://cdn.freesound.org/previews/612/612598_5674468-lq.mp3';

  Future<void> init() async {
    for (final entry in _sfx.entries) {
      final p = AudioPlayer();
      await p.setVolume(0.8);
      _players[entry.key] = p;
    }
    final bgm = AudioPlayer();
    await bgm.setVolume(0.25);
    await bgm.setReleaseMode(ReleaseMode.loop);
    _players['bgm'] = bgm;
  }

  Future<void> play(String key) async {
    if (!sfxEnabled && key != 'bgm') return;
    try {
      final url = _sfx[key];
      if (url == null) return;
      await _players[key]?.play(UrlSource(url));
    } catch (_) {}
  }

  Future<void> startBgm() async {
    if (!bgmEnabled) return;
    try {
      await _players['bgm']?.play(UrlSource(_bgmUrl));
    } catch (_) {}
  }

  Future<void> stopBgm() async {
    try { await _players['bgm']?.stop(); } catch (_) {}
  }

  void dispose() {
    for (final p in _players.values) { p.dispose(); }
  }
}
