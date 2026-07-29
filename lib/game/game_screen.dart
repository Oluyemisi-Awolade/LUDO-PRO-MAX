// lib/screens/game_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import '../widgets/board_widget.dart';
import '../widgets/dice_widget.dart';
import '../widgets/common_widgets.dart';
import 'menu_screen.dart';

class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final _chatCtrl = TextEditingController();
  bool _showChat  = false;
  bool _gameOverShown = false;

  @override
  void initState() {
    super.initState();
    ref.read(audioServiceProvider).startBgm();
  }

  @override
  void dispose() {
    _chatCtrl.dispose();
    ref.read(audioServiceProvider).stopBgm();
    super.dispose();
  }

  Future<void> _roll() async {
    final gs = ref.read(gameProvider);
    if (!gs.isPlayerTurn || gs.diceRolled || gs.gameOver) return;
    await ref.read(gameProvider.notifier).rollDice();
  }

  void _goBack() {
    ref.read(audioServiceProvider).stopBgm();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MenuScreen()),
    );
  }

  void _checkGameOver(GameState gs) {
    if (gs.gameOver && gs.winner != null && !_gameOverShown) {
      _gameOverShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showGameOverDialog(gs);
      });
    }
  }

  void _showGameOverDialog(GameState gs) {
    final winner = gs.winner!;
    final myWon  = winner == gs.playerIndex;

    // Placement/reward text only makes real sense in multiplayer mode,
    // where the game plays out until a single player remains and
    // finishedPlayers accumulates 1st/2nd/3rd/4th over time. In vsBot
    // mode the game ends the instant the FIRST player finishes, so
    // nobody else ever gets a genuine placement — showing "2nd" for
    // someone who was nowhere close to finishing would be made up.
    late final String placementLine;
    String? rewardLine;

    if (gs.mode == GameMode.vsBot) {
      if (myWon) {
        placementLine = 'You Won! 🏆';
        rewardLine = '+${kPlaceRewards[0]} coins 🪙';
      } else {
        placementLine = "You didn't finish this time";
        rewardLine = null;
      }
    } else {
      final my    = gs.finishedPlayers.indexOf(gs.playerIndex);
      final place = my == -1 ? gs.finishedPlayers.length : my;
      const labels = ['🥇 1st', '🥈 2nd', '🥉 3rd', '4th'];
      placementLine = 'You finished: ${labels[place.clamp(0, 3)]}';
      rewardLine = '+${kPlaceRewards[place.clamp(0, 3)]} coins 🪙';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏆', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 8),
              Text('Game Over!',
                  style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text('${kPlayerNames[winner]} wins!',
                  style: TextStyle(
                      fontSize: 18,
                      color: kPlayerColors[winner],
                      fontWeight: FontWeight.w700)),
              const Divider(height: 24, color: AppColors.border),
              Text(placementLine,
                  style: Theme.of(context).textTheme.bodyLarge),
              if (rewardLine != null) ...[
                const SizedBox(height: 4),
                Text(rewardLine,
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
              const Divider(height: 24, color: AppColors.border),
              SupportCard(
                onDonate: () async {
                  final url = Uri.parse(kFlutterwaveUrl);
                  if (await canLaunchUrl(url)) launchUrl(url);
                },
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final freshGs = ref.read(gameProvider);
                      try {
                        Navigator.of(dialogContext, rootNavigator: true)
                            .pop();
                        _gameOverShown = false;
                        ref.read(gameProvider.notifier).setupGame(
                          mode:        freshGs.mode,
                          difficulty:  freshGs.botDifficulty,
                          twoDice:     freshGs.twoDiceMode,
                          numPlayers:  freshGs.numPlayers,
                          playerColor: freshGs.playerColorIndex,
                        );
                        ref.read(audioServiceProvider).startBgm();
                      } catch (e, st) {
                        debugPrint('Play Again failed: $e\n$st');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Restart failed: $e')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.violet),
                    child: const Text('Play Again'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext, rootNavigator: true).pop();
                      _gameOverShown = false;
                      _goBack();
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade700),
                    child: const Text('Menu'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gs    = ref.watch(gameProvider);
    final audio = ref.read(audioServiceProvider);
    _checkGameOver(gs);

    final canRoll  = gs.isPlayerTurn && !gs.diceRolled && !gs.gameOver;

    String rollLabel;
    Color  rollColor;
    if (gs.gameOver) {
      rollLabel = '🏆 ${kPlayerNames[gs.winner!]} Wins!';
      rollColor = Colors.green.shade700;
    } else if (gs.isPlayerTurn && !gs.diceRolled) {
      rollLabel = '🎲 Roll Dice';
      rollColor = AppColors.violet;
    } else if (gs.isPlayerTurn && gs.diceRolled) {
      rollLabel = '👆 Tap your token';
      rollColor = Colors.orange.shade700;
    } else {
      rollLabel = '⏳ ${kPlayerNames[gs.currentTurn]}\'s Turn';
      rollColor = Colors.blueGrey.shade700;
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  color: Colors.white,
                  onPressed: _goBack,
                ),
                Expanded(child: _StatusBar(gs: gs)),
                IconButton(
                  icon: Icon(audio.sfxEnabled
                      ? Icons.volume_up_rounded
                      : Icons.volume_off_rounded, size: 20),
                  color: Colors.white70,
                  onPressed: () =>
                      setState(() => audio.sfxEnabled = !audio.sfxEnabled),
                ),
                IconButton(
                  icon: Icon(audio.bgmEnabled
                      ? Icons.music_note_rounded
                      : Icons.music_off_rounded, size: 20),
                  color: Colors.white70,
                  onPressed: () {
                    setState(() => audio.bgmEnabled = !audio.bgmEnabled);
                    if (audio.bgmEnabled) audio.startBgm();
                    else audio.stopBgm();
                  },
                ),
                if (gs.mode == GameMode.online)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 20),
                    color: Colors.white70,
                    onPressed: () =>
                        setState(() => _showChat = !_showChat),
                  ),
              ]),
            ),

            // ── Player strip ──────────────────────────────────────────────
            Container(
              color: AppColors.bg,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (int i = 0; i < gs.numPlayers; i++)
                    PlayerChip(
                      index:    i,
                      name:     gs.playerNames[i] ?? kPlayerNames[i],
                      active:   i == gs.currentTurn && !gs.gameOver,
                      finished: gs.finishedPlayers.contains(i),
                      color:    kPlayerColors[i],
                    ),
                ],
              ),
            ),

            // ── Board ─────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: const BoardWidget(),
              ),
            ),

            // ── Two dice + Roll button ─────────────────────────────────────
            Container(
              color: AppColors.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Always show BOTH dice
                  Row(children: [
                    DiceWidget(value: gs.dice1),
                    if (gs.twoDiceMode) ...[
                      const SizedBox(width: 10),
                      DiceWidget(value: gs.dice2),
                    ],
                    if (gs.diceRolled) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.violet.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.violet),
                        ),
                        child: Text(
                          '= ${gs.totalDice}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16),
                        ),
                      ),
                    ],
                  ]),
                  RollButton(
                    label:     rollLabel,
                    enabled:   canRoll,
                    color:     rollColor,
                    onPressed: canRoll ? _roll : null,
                  ),
                ],
              ),
            ),

            // ── Emote bar ─────────────────────────────────────────────────
            Container(
              color: AppColors.bg,
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                itemCount: kEmotes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () =>
                      ref.read(gameProvider.notifier).sendChat(kEmotes[i]),
                  child: Container(
                    width: 36, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(kEmotes[i],
                        style: const TextStyle(fontSize: 16)),
                  ),
                ),
              ),
            ),

            // ── Chat (online only) ─────────────────────────────────────────
            if (gs.mode == GameMode.online && _showChat)
              _ChatPanel(chatCtrl: _chatCtrl, gs: gs),
          ],
        ),
      ),
    );
  }
}

// ── Status bar ────────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final GameState gs;
  const _StatusBar({required this.gs});

  @override
  Widget build(BuildContext context) {
    final ud = gs.userData;
    if (ud == null) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StatChip(emoji: '🪙', value: '${ud.coins}'),
      const SizedBox(width: 6),
      StatChip(emoji: '📊', value: '${ud.elo}'),
    ]);
  }
}

// ── Chat panel ────────────────────────────────────────────────────────────────
class _ChatPanel extends ConsumerWidget {
  final TextEditingController chatCtrl;
  final GameState gs;
  const _ChatPanel({required this.chatCtrl, required this.gs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.surface,
      height: 140,
      padding: const EdgeInsets.all(8),
      child: Column(children: [
        Expanded(
          child: ListView.builder(
            reverse: true,
            itemCount: gs.chatMessages.length,
            itemBuilder: (_, i) {
              final msg = gs.chatMessages[gs.chatMessages.length - 1 - i];
              final pi  = kPlayerNames.indexOf(msg.player).clamp(0, 3);
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: kPlayerColors[pi],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(msg.player,
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(msg.msg,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ),
                ]),
              );
            },
          ),
        ),
        Row(children: [
          Expanded(
            child: TextField(
              controller: chatCtrl,
              style:
                  const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText:    'Message…',
                hintStyle:   const TextStyle(color: Colors.white30),
                filled:      true,
                fillColor:   AppColors.card,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 18),
            color: AppColors.violetLit,
            onPressed: () {
              if (chatCtrl.text.trim().isEmpty) return;
              ref
                  .read(gameProvider.notifier)
                  .sendChat(chatCtrl.text.trim());
              chatCtrl.clear();
            },
          ),
        ]),
      ]),
    );
  }
}
