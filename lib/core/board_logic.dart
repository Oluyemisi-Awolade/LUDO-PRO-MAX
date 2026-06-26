// lib/core/board_logic.dart
import 'constants.dart';

// ── Path index ────────────────────────────────────────────────────────────────
// Returns the logical progress of a token on the board.
//  -1  → in nest
//  0–51 → outer track (relative to player's start)
//  100–105 → inside home column (0 = first cell, 5 = last before home)
//  200 → centre / finished
int pathIndex(int player, List<int> pos) {
  // In nest?
  for (final np in kNestPositions[player]) {
    if (np[0] == pos[0] && np[1] == pos[1]) return -1;
  }

  // Finished?
  if (pos[0] == kFinalHome[0] && pos[1] == kFinalHome[1]) return 200;

  // In home column?
  final hp = kHousePaths[player];
  for (int i = 0; i < hp.length; i++) {
    if (hp[i][0] == pos[0] && hp[i][1] == pos[1]) return 100 + i;
  }

  // On outer track?
  final trackLen = kTrackPath.length;
  final startPos = kStartPositions[player];
  int si = -1, pi = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == startPos[0] && kTrackPath[i][1] == startPos[1]) si = i;
    if (kTrackPath[i][0] == pos[0] && kTrackPath[i][1] == pos[1]) pi = i;
  }
  if (si != -1 && pi != -1) return (pi - si + trackLen) % trackLen;

  return -2; // off-board (shouldn't happen)
}

// ── Can a token move? ─────────────────────────────────────────────────────────
bool canMove(int player, List<List<int>> tokens, int tokenIdx, int steps) {
  final pidx = pathIndex(player, tokens[tokenIdx]);
  if (pidx == -1)  return steps == 6;      // must roll 6 to leave nest
  if (pidx == 200) return false;            // already home
  if (pidx >= 100) {
    final homeSteps = (pidx - 100) + steps;
    return homeSteps <= 5 || homeSteps == 6; // exact 6 to reach centre
  }
  // On outer track: will we overshoot home column?
  final trackLen = kTrackPath.length;
  final rem = trackLen - pidx;             // steps remaining on outer track
  if (steps >= rem) {
    final hs = steps - rem;                // steps into home column
    return hs <= 6;
  }
  return true;
}

// ── Calculate new position ────────────────────────────────────────────────────
List<int> calcNewPos(int player, List<List<int>> tokens, int tokenIdx, int steps) {
  final pos  = tokens[tokenIdx];
  final pidx = pathIndex(player, pos);

  if (pidx == -1) return List<int>.from(kStartPositions[player]);

  if (pidx >= 100) {
    final ni = (pidx - 100) + steps;
    if (ni < 6) return List<int>.from(kHousePaths[player][ni]);
    return List<int>.from(kFinalHome);
  }

  // On outer track
  final trackLen = kTrackPath.length;
  int ti = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == pos[0] && kTrackPath[i][1] == pos[1]) { ti = i; break; }
  }
  final startPos = kStartPositions[player];
  int si = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == startPos[0] && kTrackPath[i][1] == startPos[1]) { si = i; break; }
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
    tokens.every((p) => p[0] == kFinalHome[0] && p[1] == kFinalHome[1]);

// ── ELO ──────────────────────────────────────────────────────────────────────
int newElo(int ra, int rb, {required bool won}) {
  final ea = 1 / (1 + (10 * ((rb - ra) / 400)).toDouble().abs().clamp(0, 1e9));
  return (ra + kEloK * ((won ? 1 : 0) - ea)).round();
}

// ── Movable tokens for a player ───────────────────────────────────────────────
List<int> movableTokens(int player, List<List<int>> tokens, int steps) =>
    [for (int i = 0; i < tokens.length; i++)
      if (canMove(player, tokens, i, steps)) i];
