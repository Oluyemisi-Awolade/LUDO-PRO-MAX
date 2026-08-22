// lib/widgets/board_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import '../game/game_state.dart';
import '../game/game_notifier.dart';
import 'board_painter.dart';

// Does landing on `pos` capture an opponent token?
// FIX: takes the active player explicitly (gs.currentTurn) instead of
// reading gs.playerIndex internally — see note below on why.
bool _landsOnOpponent(GameState gs, int activePlayer, List<int> pos) {
  if (isSafe(pos)) return false;
  for (final e in gs.tokens.entries) {
    if (e.key == activePlayer) continue;
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
          // FIX: was `gs.isPlayerTurn`, which only ever holds true for the
          // color that originally set up the game (gs.playerIndex). That's
          // correct for vsBot/Online (the human only ever taps on their
          // own turn), but wrong for local pass-and-play, where every
          // color's turn is a real, tappable turn on this same device.
          // canCurrentPlayerAct is the same fix already applied to the
          // Roll button — this makes the board consistent with it.
          if (!gs.canCurrentPlayerAct || !gs.diceRolled || gs.gameOver) return;

          final box = context.findRenderObject() as RenderBox;
          final size = box.size;
          final local = details.localPosition;
          final cellW = size.width / kBoardSize;
          final cellH = size.height / kBoardSize;
          final col = (local.dx / cellW).floor().clamp(0, kBoardSize - 1);
          final row = (local.dy / cellH).floor().clamp(0, kBoardSize - 1);

          // FIX: was gs.tokens[gs.playerIndex] — always looked up the
          // ORIGINAL setup player's tokens, never whoever's turn it
          // actually is. In local multiplayer this meant tapping Green's
          // token (on Green's turn) silently looked for a match among
          // Red's token positions instead — found nothing, did nothing,
          // with no visible error. gs.currentTurn is correct in every
          // mode: in vsBot/Online, canCurrentPlayerAct above already
          // guarantees currentTurn == playerIndex by the time we get
          // here, so this is a strict improvement, not a behavior change
          // for those modes.
          final activePlayer = gs.currentTurn;
          final toks = gs.tokens[activePlayer];
          if (toks == null) return;

          for (int ti = 0; ti < toks.length; ti++) {
            if (toks[ti][0] == row && toks[ti][1] == col) {
              final okD1 =
                  gs.dice1 > 0 && canMove(activePlayer, toks, ti, gs.dice1);
              final okD2 = gs.twoDiceMode &&
                  gs.dice2 > 0 &&
                  canMove(activePlayer, toks, ti, gs.dice2);

              int? dieChoice;
              if (okD1 && okD2) {
                // Both dice would move this token — prefer whichever
                // one lands on an opponent for a capture.
                final pos1 = calcNewPos(activePlayer, toks, ti, gs.dice1);
                final pos2 = calcNewPos(activePlayer, toks, ti, gs.dice2);
                final cap1 = _landsOnOpponent(gs, activePlayer, pos1);
                final cap2 = _landsOnOpponent(gs, activePlayer, pos2);
                dieChoice = (cap2 && !cap1) ? 2 : 1;
              } else if (okD1) {
                dieChoice = 1;
              } else if (okD2) {
                dieChoice = 2;
              }

              if (dieChoice != null) {
                ref.read(gameProvider.notifier).moveToken(
                      activePlayer,
                      ti,
                      dieChoice: dieChoice,
                    );
                return;
              }
            }
          }
        },
        child: CustomPaint(
          painter: BoardPainter(
            tokens: gs.tokens,
            currentTurn: gs.currentTurn,
            diceRolled: gs.diceRolled,
            playerIndex: gs.playerIndex,
          ),
        ),
      ),
    );
  }
}
