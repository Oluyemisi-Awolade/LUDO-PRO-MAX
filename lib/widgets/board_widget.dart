// lib/widgets/board_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import '../game/game_notifier.dart';
import 'board_painter.dart';

class BoardWidget extends ConsumerWidget {
  const BoardWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gs = ref.watch(gameProvider);

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        onTapUp: (details) {
          // Only respond when it's the player's turn and dice have been rolled
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
              if (canMove(gs.playerIndex, toks, ti, gs.totalDice)) {
                ref.read(gameProvider.notifier).moveToken(gs.playerIndex, ti);
                return;
              }
            }
          }
        },
        child: CustomPaint(
          painter: BoardPainter(
            tokens:       gs.tokens,
            currentTurn:  gs.currentTurn,
            diceRolled:   gs.diceRolled,
            playerIndex:  gs.playerIndex,
          ),
        ),
      ),
    );
  }
}
