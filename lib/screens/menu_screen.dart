// lib/screens/menu_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
import 'tournament_screen.dart';
import 'leaderboard_screen.dart';
import 'login_screen.dart';

class MenuScreen extends ConsumerWidget {
  const MenuScreen({super.key});

  void _startBot(BuildContext ctx, WidgetRef ref, BotDifficulty diff, {bool twoDice = false}) {
    ref.read(gameProvider.notifier).setupGame(
      mode: GameMode.vsBot, difficulty: diff, twoDice: twoDice,
    );
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  void _startLocal(BuildContext ctx, WidgetRef ref, int n) {
    ref.read(gameProvider.notifier).setupGame(
      mode: GameMode.localMultiplayer, numPlayers: n,
    );
    Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ud = ref.watch(gameProvider).userData;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(title: 'Ludo Pro Max'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile card
                    _ProfileCard(ud: ud),
                    const SizedBox(height: 16),

                    // VS AI
                    const LabelDivider('VS AI'),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: 'Easy Bot  😊',
                      color: Colors.green.shade700,
                      onTap: () => _startBot(context, ref, BotDifficulty.easy),
                    ),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: 'Hard Bot  😤',
                      color: Colors.orange.shade700,
                      onTap: () => _startBot(context, ref, BotDifficulty.hard),
                    ),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: 'Hardest Bot  💀',
                      color: Colors.red.shade700,
                      onTap: () => _startBot(context, ref, BotDifficulty.hardest),
                    ),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: '2-Dice vs Bot  🎲🎲',
                      color: Colors.deepPurple.shade600,
                      onTap: () => _startBot(context, ref, BotDifficulty.hard, twoDice: true),
                    ),

                    // Local
                    const SizedBox(height: 16),
                    const LabelDivider('LOCAL PLAY'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _SmallBtn(label: '2P', color: Colors.blue.shade700,
                            onTap: () => _startLocal(context, ref, 2)),
                        const SizedBox(width: 8),
                        _SmallBtn(label: '3P', color: Colors.teal.shade700,
                            onTap: () => _startLocal(context, ref, 3)),
                        const SizedBox(width: 8),
                        _SmallBtn(label: '4P', color: Colors.indigo.shade600,
                            onTap: () => _startLocal(context, ref, 4)),
                      ],
                    ),

                    // Online
                    const SizedBox(height: 16),
                    const LabelDivider('ONLINE'),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: 'Online Multiplayer  🌍',
                      icon: Icons.wifi_rounded,
                      color: Colors.cyan.shade700,
                      onTap: () {
                        if (ud == null || ud.uid == 'offline') {
                          showSnack(context, 'Log in to play online', color: Colors.red.shade700);
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LobbyScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: 'Tournaments  🏆',
                      icon: Icons.emoji_events_rounded,
                      color: Colors.amber.shade700,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TournamentScreen()),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _MenuBtn(
                      label: 'Leaderboard  📊',
                      icon: Icons.leaderboard_rounded,
                      color: Colors.pink.shade700,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                      ),
                    ),

                    const SizedBox(height: 20),
                    SupportCard(
                      onDonate: () async {
                        final url = Uri.parse(kFlutterwaveUrl);
                        if (await canLaunchUrl(url)) launchUrl(url);
                      },
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        ref.read(gameProvider.notifier).clearUser();
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      child: const Text('Log Out',
                          style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────
class _ProfileCard extends StatelessWidget {
  final UserData? ud;
  const _ProfileCard({this.ud});

  @override
  Widget build(BuildContext context) {
    final name  = ud?.displayName ?? 'Player';
    final coins = ud?.coins ?? 0;
    final wins  = ud?.wins  ?? 0;
    final elo   = ud?.elo   ?? kDefaultElo;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.violet,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'P',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    StatChip(emoji: '🪙', value: '$coins'),
                    StatChip(emoji: '🏆', value: '${wins}W'),
                    StatChip(emoji: '📊', value: '$elo ELO'),
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

class _MenuBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;

  const _MenuBtn({required this.label, required this.color, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.centerLeft,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallBtn({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}
