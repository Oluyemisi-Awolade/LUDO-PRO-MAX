// lib/widgets/board_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import '../game/game_notifier.dart';
import 'board_painter.dart';

bool _landsOnOpponent(GameState gs, List<int> pos) {
  if (isSafe(pos)) return false;
  for (final e in gs.tokens.entries) {
    if (e.key == gs.playerIndex) continue;
    for (final tp in e.value) {
      if (tp[0] == pos[0] && tp[1] == pos[1]) return true;
    }
  }
  return false;
}
class BoardWidget extends ConsumerWidget {
  const BoardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gs = ref.watch(gameProvider);

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTapUp: (details) {
          if (!gs.isPlayerTurn || !gs.diceRolled || gs.gameOver) return;

          final box   = context.findRenderObject() as RenderBox;
          final size  = box.size;
          final local = details.localPosition;
          final cellW = size.width  / kBoardSize;
          final cellH = size.height / kBoardSize;
          final col   = (local.dx / cellW).floor().clamp(0, kBoardSize - 1);
          final row   = (local.dy / cellH).floor().clamp(0, kBoardSize - 1);

          final toks = gs.tokens[gs.playerIndex];
          if (toks == null) return;

          for (int ti = 0; ti < toks.length; ti++) {
            if (toks[ti][0] == row && toks[ti][1] == col) {
              final okD1 = gs.dice1 > 0 && canMove(gs.playerIndex, toks, ti, gs.dice1);
              final okD2 = gs.twoDiceMode && gs.dice2 > 0 &&
                  canMove(gs.playerIndex, toks, ti, gs.dice2);

              int? dieChoice;
              if (okD1 && okD2) {
                final pos1 = calcNewPos(gs.playerIndex, toks, ti, gs.dice1);
                final pos2 = calcNewPos(gs.playerIndex, toks, ti, gs.dice2);
                final cap1 = _landsOnOpponent(gs, pos1);
                final cap2 = _landsOnOpponent(gs, pos2);
                dieChoice = (cap2 && !cap1) ? 2 : 1;
              } else if (okD1) {
                dieChoice = 1;
              } else if (okD2) {
                dieChoice = 2;
              }

              if (dieChoice != null) {
                ref.read(gameProvider.notifier)
                    .moveToken(gs.playerIndex, ti, dieChoice: dieChoice);
                return;
              }
            }
          }
        },
        child: CustomPaint(
          painter: BoardPainter(
            tokens:      gs.tokens,
            currentTurn: gs.currentTurn,
            diceRolled:  gs.diceRolled,
            playerIndex: gs.playerIndex,
          ),
        ),
      ),
    );
  }
}
