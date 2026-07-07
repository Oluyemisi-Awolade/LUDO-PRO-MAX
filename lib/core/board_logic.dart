// lib/core/board_logic.dart
import 'constants.dart';

// ── Path index ────────────────────────────────────────────────────────────────
//  -1   → in nest
//  0–51 → outer track (relative to player's start)
//  100–105 → home column
//  200  → finished / centre
int pathIndex(int player, List<int> pos) {
  for (final np in kNestPositions[player]) {
    if (np[0] == pos[0] && np[1] == pos[1]) return -1;
  }
  if (pos[0] == kFinalHome[0] && pos[1] == kFinalHome[1]) return 200;
  final hp = kHousePaths[player];
  for (int i = 0; i < hp.length; i++) {
    if (hp[i][0] == pos[0] && hp[i][1] == pos[1]) return 100 + i;
  }
  final trackLen = kTrackPath.length;
  final startPos = kStartPositions[player];
  int si = -1, pi = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == startPos[0] &&
        kTrackPath[i][1] == startPos[1]) si = i;
    if (kTrackPath[i][0] == pos[0] &&
        kTrackPath[i][1] == pos[1]) pi = i;
  }
  if (si != -1 && pi != -1) return (pi - si + trackLen) % trackLen;
  return -2;
}

// ── Can a token move? ─────────────────────────────────────────────────────────
// KEY RULE: a token in the nest can ONLY leave if at least one die shows 6.
// The total (e.g. 5+1=6) does NOT count — an actual 6 face is required.
//
// [dice1] and [dice2] are the individual die values (dice2=0 for single-die mode).
// [steps] is the total used for movement (dice1+dice2 or just dice1).
bool canMove(
  int player,
  List<List<int>> tokens,
  int tokenIdx,
  int steps, {
  int dice1 = 0,
  int dice2 = 0,
}) {
  final pidx = pathIndex(player, tokens[tokenIdx]);

  if (pidx == -1) {
    // In nest: MUST have an actual 6 on one of the dice
    return dice1 == 6 || dice2 == 6;
  }

  if (pidx == 200) return false; // already finished

  if (pidx >= 100) {
    // In home column — can move if we don't overshoot
    final homeSteps = (pidx - 100) + steps;
    return homeSteps <= 5 || homeSteps == 6;
  }

  // On outer track — check we don't overshoot home column
  final trackLen = kTrackPath.length;
  final rem = trackLen - pidx;
  if (steps >= rem) {
    final hs = steps - rem;
    return hs <= 6;
  }
  return true;
}

// ── Calculate new position ────────────────────────────────────────────────────
List<int> calcNewPos(
    int player, List<List<int>> tokens, int tokenIdx, int steps) {
  final pos  = tokens[tokenIdx];
  final pidx = pathIndex(player, pos);

  if (pidx == -1) return List<int>.from(kStartPositions[player]);

  if (pidx >= 100) {
    final ni = (pidx - 100) + steps;
    if (ni < 6) return List<int>.from(kHousePaths[player][ni]);
    return List<int>.from(kFinalHome);
  }

  final trackLen = kTrackPath.length;
  int ti = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == pos[0] &&
        kTrackPath[i][1] == pos[1]) { ti = i; break; }
  }
  final startPos = kStartPositions[player];
  int si = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == startPos[0] &&
        kTrackPath[i][1] == startPos[1]) { si = i; break; }
  }
  final relIdx = (ti - si + trackLen) % trackLen;
  final rem    = trackLen - relIdx;

  if (steps >= rem) {
    final hs = steps - rem;
    if (hs < 6) return List<int>.from(kHousePaths[player][hs]);
    return List<int>.from(kFinalHome);
  }

  final newTi = (ti + steps) % trackLen;
  return List<int>.from(kTrackPath[newTi]);
}

// ── All tokens home? ──────────────────────────────────────────────────────────
bool allHome(List<List<int>> tokens) =>
    tokens.every((p) =>
        p[0] == kFinalHome[0] && p[1] == kFinalHome[1]);

// ── ELO ───────────────────────────────────────────────────────────────────────
int newElo(int ra, int rb, {required bool won}) {
  final ea = 1 / (1 + (10 * ((rb - ra) / 400)).toDouble().abs().clamp(0, 1e9));
  return (ra + kEloK * ((won ? 1 : 0) - ea)).round();
}

// ── Movable tokens ────────────────────────────────────────────────────────────
// Must pass dice1 and dice2 so nest-exit rule works correctly.
List<int> movableTokens(
  int player,
  List<List<int>> tokens,
  int steps, {
  int dice1 = 0,
  int dice2 = 0,
}) =>
    [
      for (int i = 0; i < tokens.length; i++)
        if (canMove(player, tokens, i, steps,
            dice1: dice1, dice2: dice2)) i
    ];
