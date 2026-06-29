// lib/screens/leaderboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  bool _loading = true;
  List<_LeaderEntry> _entries = [];

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
      final raw = await ref.read(firebaseServiceProvider).getLeaderboard(tok);
      if (raw == null) { setState(() => _loading = false); return; }

      final entries = <_LeaderEntry>[];
      for (final e in raw.entries) {
        final uid = e.key.toString();
        final u   = e.value;
        if (u is! Map) continue;
        entries.add(_LeaderEntry(
          uid:   uid,
          name:  u['displayName']?.toString() ?? u['email']?.toString() ?? '?',
          elo:   (u['elo'] as num?)?.toInt() ?? kDefaultElo,
          wins:  (u['wins'] as num?)?.toInt() ?? 0,
        ));
      }
      entries.sort((a, b) => b.elo.compareTo(a.elo));

      setState(() => _entries = entries.take(20).toList());
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', color: Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = ref.read(gameProvider).userData?.uid;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Leaderboard 📊',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                color: AppColors.violet,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.violet))
                    : _entries.isEmpty
                        ? const Center(
                            child: Text('No data yet 🤷',
                                style: TextStyle(color: Colors.white54)))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                            itemCount: _entries.length,
                            itemBuilder: (_, i) {
                              final e    = _entries[i];
                              final isMe = e.uid == myUid;
                              return _LeaderCard(
                                rank: i + 1,
                                entry: e,
                                isMe: isMe,
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data class ────────────────────────────────────────────────────────────────
class _LeaderEntry {
  final String uid, name;
  final int elo, wins;
  const _LeaderEntry(
      {required this.uid,
      required this.name,
      required this.elo,
      required this.wins});
}

// ── Card ──────────────────────────────────────────────────────────────────────
class _LeaderCard extends StatelessWidget {
  final int rank;
  final _LeaderEntry entry;
  final bool isMe;

  const _LeaderCard(
      {required this.rank, required this.entry, required this.isMe});

  String get _medal {
    switch (rank) {
      case 1: return '🥇';
      case 2: return '🥈';
      case 3: return '🥉';
      default: return '  #$rank';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? AppColors.violet.withOpacity(0.15) : AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? AppColors.violetLit : AppColors.border,
          width: isMe ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(_medal,
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.name.length > 18
                            ? '${entry.name.substring(0, 18)}…'
                            : entry.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isMe ? AppColors.violetLit : Colors.white,
                        ),
                      ),
                    ),
                    if (isMe)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.violet.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('You',
                            style: TextStyle(
                                fontSize: 9,
                                color: AppColors.violetLit,
                                fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StatChip(emoji: '📊', value: '${entry.elo} ELO'),
                    const SizedBox(width: 6),
                    StatChip(emoji: '🏆', value: '${entry.wins}W'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
