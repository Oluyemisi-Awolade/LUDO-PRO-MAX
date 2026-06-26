// lib/core/constants.dart
import 'package:flutter/material.dart';

// ── Board geometry ────────────────────────────────────────────────────────────
const int kBoardSize = 15;

/// Nest positions for each of the 4 players (row, col).
const List<List<List<int>>> kNestPositions = [
  [[1,1],[1,4],[4,1],[4,4]],   // Red
  [[1,10],[1,13],[4,10],[4,13]], // Green
  [[10,10],[10,13],[13,10],[13,13]], // Yellow
  [[10,1],[10,4],[13,1],[13,4]],  // Blue
];

/// Starting squares on the outer track.
const List<List<int>> kStartPositions = [
  [6,1], [1,8], [8,13], [13,6],
];

/// The 52-cell outer track (row, col) starting from Red's exit.
const List<List<int>> kTrackPath = [
  [6,1],[6,2],[6,3],[6,4],[6,5],
  [5,6],[4,6],[3,6],[2,6],[1,6],[0,6],
  [0,7],[0,8],
  [1,8],[2,8],[3,8],[4,8],[5,8],
  [6,9],[6,10],[6,11],[6,12],[6,13],[6,14],
  [7,14],
  [8,14],[8,13],[8,12],[8,11],[8,10],[8,9],
  [9,8],[10,8],[11,8],[12,8],[13,8],[14,8],
  [14,7],
  [14,6],[13,6],[12,6],[11,6],[10,6],[9,6],
  [8,5],[8,4],[8,3],[8,2],[8,1],[8,0],
  [7,0],[6,0],
];

/// 6-cell coloured home-column leading to centre, one per player.
const List<List<List<int>>> kHousePaths = [
  [[7,1],[7,2],[7,3],[7,4],[7,5],[7,6]],   // Red  → east
  [[1,7],[2,7],[3,7],[4,7],[5,7],[6,7]],   // Green → south
  [[7,13],[7,12],[7,11],[7,10],[7,9],[7,8]], // Yellow → west
  [[13,7],[12,7],[11,7],[10,7],[9,7],[8,7]], // Blue  → north
];

/// The single centre finish square.
const List<int> kFinalHome = [7,7];

/// Squares where captures are not allowed.
const Set<String> kSafeSquares = {
  '6,2','2,6','6,12','8,2','12,8','8,12','2,8','12,6',
};

String posKey(List<int> pos) => '${pos[0]},${pos[1]}';
bool isSafe(List<int> pos) => kSafeSquares.contains(posKey(pos));

// ── Player meta ───────────────────────────────────────────────────────────────
const List<String> kPlayerNames  = ['Red', 'Green', 'Yellow', 'Blue'];

const List<Color> kPlayerColors = [
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFF1E88E5),
];

// ── Dice ──────────────────────────────────────────────────────────────────────
const Map<int, String> kDiceEmoji = {
  0: '⚀', 1: '⚀', 2: '⚁', 3: '⚂', 4: '⚃', 5: '⚄', 6: '⚅',
};

// ── Game settings ─────────────────────────────────────────────────────────────
const int kDefaultElo = 1000;
const int kEloK       = 32;

// ── Emotes ────────────────────────────────────────────────────────────────────
const List<String> kEmotes = ['😂','😡','😎','🎉','😭','👍','🤔','💀','🔥','👑'];

// ── Coin rewards ─────────────────────────────────────────────────────────────
const List<int> kPlaceRewards = [300, 200, 100, 50];

// ── App ───────────────────────────────────────────────────────────────────────
const String kAppVersion      = '2.0.0';
const String kFlutterwaveUrl  = 'https://flutterwave.com/pay/ou2066snurqa';
