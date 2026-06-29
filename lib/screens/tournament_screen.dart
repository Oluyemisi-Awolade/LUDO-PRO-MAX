// lib/screens/tournament_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../game/game_notifier.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class TournamentScreen extends ConsumerStatefulWidget {
  const TournamentScreen({super.key});

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends ConsumerState<TournamentScreen> {
  bool _loading = true;
  Map<String, dynamic> _tournaments = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final gs  = ref.read(gameProvider);
      final tok = gs.userData?.idToken ?? '';
      final raw = await ref.read(firebaseServiceProvider).getTournaments(tok);
      setState(() {
        _tournaments = raw != null
            ? {for (final e in raw.entries) e.key.toString(): e.value}
            : {};
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', color: Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final gs   = ref.read(gameProvider);
    final ud   = gs.userData;
    if (ud == null) return;
    final name = 'Tournament ${Random().nextInt(900) + 100}';
    final tid  = 't_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await ref.read(firebaseServiceProvider).putTournament(tid, {
        'name': name,
        'created_by': ud.uid,
        'prize_coins': 500,
        'state': 'open',
        'players': {
          ud.uid: {'email': ud.email, 'elo': ud.elo},
        },
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, ud.idToken ?? '');
      if (mounted) showSnack(context, '\'$name\' created! 🎉', color: Colors.green.shade700);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', color: Colors.red.shade700);
    }
  }

  Future<void> _join(String tid) async {
    final gs = ref.read(gameProvider);
    final ud = gs.userData;
    if (ud == null) return;
    try {
      await ref.read(firebaseServiceProvider).joinTournament(
        tid, ud.uid,
        {'email': ud.email, 'elo': ud.elo},
        ud.idToken ?? '',
      );
      if (mounted) showSnack(context, 'Joined! 🏆', color: Colors.green.shade700);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', color: Colors.red.shade700);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Tournaments 🏆',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.violet,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create Tournament'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_loading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: CircularProgressIndicator(color: AppColors.gold),
                          ),
                        )
                      else if (_tournaments.isEmpty)
                        _EmptyState(
                          emoji: '🏆',
                          label: 'No active tournaments',
                          sub: 'Create one and invite friends!',
                        )
                      else
                        ..._tournaments.entries.map((e) {
                          final tid  = e.key;
                          final t    = e.value as Map;
                          final cnt  = (t['players'] as Map?)?.length ?? 0;
                          final prize = (t['prize_coins'] as num?)?.toInt() ?? 500;
                          final ud   = ref.read(gameProvider).userData;
                          final joined = (t['players'] as Map?)
                                  ?.containsKey(ud?.uid ?? '') ??
                              false;
                          return _TournamentCard(
                            name:   t['name']?.toString() ?? 'Tournament',
                            players: cnt,
                            prize:  prize,
                            joined: joined,
                            onJoin: joined ? null : () => _join(tid),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────
class _TournamentCard extends StatelessWidget {
  final String name;
  final int players;
  final int prize;
  final bool joined;
  final VoidCallback? onJoin;

  const _TournamentCard({
    required this.name,
    required this.players,
    required this.prize,
    required this.joined,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: joined ? Colors.amber.shade700 : AppColors.border,
          width: joined ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          const Text('🏆', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StatChip(emoji: '👥', value: '$players/8'),
                    const SizedBox(width: 6),
                    StatChip(emoji: '🪙', value: '$prize prize'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (joined)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade800.withOpacity(0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade700),
              ),
              child: const Text('Joined ✓',
                  style: TextStyle(fontSize: 12, color: Colors.green)),
            )
          else
            ElevatedButton(
              onPressed: onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Join'),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji, label, sub;
  const _EmptyState({required this.emoji, required this.label, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(sub, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
