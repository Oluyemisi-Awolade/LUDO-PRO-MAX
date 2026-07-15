// lib/core/board_logic.dart
import 'constants.dart';

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

// Nest exit requires the die being played to actually show 6.
// Home column: 6 cells (100-105), centre = 200
bool canMove(int player, List<List<int>> tokens, int tokenIdx, int steps,
    {int dice1 = 0, int dice2 = 0}) {
  final pidx = pathIndex(player, tokens[tokenIdx]);
  if (pidx == -1) return steps == 6;
  if (pidx == 200) return false;
  if (pidx >= 100) {
    final hs = (pidx - 100) + steps;
    return hs <= 5 || hs == 6; // 6 cells then centre
  }
  final rem = kTrackPath.length - pidx - 1;
  if (steps >= rem) return (steps - rem) <= 6;
  return true;
}

List<int> calcNewPos(
    int player, List<List<int>> tokens, int tokenIdx, int steps) {
  final pos = tokens[tokenIdx];
  final pidx = pathIndex(player, pos);
  if (pidx == -1) return List<int>.from(kStartPositions[player]);
  if (pidx >= 100) {
    final ni = (pidx - 100) + steps;
    if (ni < 6) return List<int>.from(kHousePaths[player][ni]);
    return List<int>.from(kFinalHome);
  }
  final trackLen = kTrackPath.length;
  int ti = -1, si = -1;
  for (int i = 0; i < trackLen; i++) {
    if (kTrackPath[i][0] == pos[0] && kTrackPath[i][1] == pos[1]) ti = i;
    if (kTrackPath[i][0] == kStartPositions[player][0] &&
        kTrackPath[i][1] == kStartPositions[player][1]) si = i;
  }
  final relIdx = (ti - si + trackLen) % trackLen;
  final rem    = trackLen - relIdx - 1;
  if (steps >= rem) {
    final hs = steps - rem;
    if (hs < 6) return List<int>.from(kHousePaths[player][hs]);
    return List<int>.from(kFinalHome);
  }
  return List<int>.from(kTrackPath[(ti + steps) % trackLen]);
}

bool allHome(List<List<int>> tokens) =>
    tokens.every((p) => p[0] == kFinalHome[0] && p[1] == kFinalHome[1]);

int newElo(int ra, int rb, {required bool won}) {
  final ea = 1 / (1 + (10 * ((rb - ra) / 400)).toDouble().abs().clamp(0, 1e9));
  return (ra + kEloK * ((won ? 1 : 0) - ea)).round();
}

List<int> movableTokens(int player, List<List<int>> tokens, int steps,
        {int dice1 = 0, int dice2 = 0}) =>
    [
      for (int i = 0; i < tokens.length; i++)
        if (canMove(player, tokens, i, steps, dice1: dice1, dice2: dice2)) i
    ];
