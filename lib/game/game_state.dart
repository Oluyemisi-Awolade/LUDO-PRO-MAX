// lib/game/game_state.dart
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import 'dart:math';

enum GameMode       { vsBot, localMultiplayer, online }
enum BotDifficulty  { easy, hard, hardest }
enum GameStatus     { waiting, playing, finished }

List<List<int>> _defaultTokens(int player) =>
    kNestPositions[player].map((p) => List<int>.from(p)).toList();

@immutable
class GameState {
  final GameMode      mode;
  final BotDifficulty botDifficulty;
  final GameStatus    status;
  final bool          twoDiceMode;
  final int           numPlayers;
  final int           currentTurn;
  final int           playerIndex;
  final int           playerColorIndex;   // chosen colour (0-3)
  final String        playerDisplayName;  // chosen name
  final Map<int, String> playerNames;
  final Map<int, List<List<int>>> tokens;
  final int           dice1;
  final int           dice2;
  final int           sixCount;
  final bool          extraTurn;
  final List<int>     finishedPlayers;
  final int?          winner;
  final List<ChatMessage> chatMessages;
  final String?       roomId;
  final UserData?     userData;

  const GameState({
    this.mode             = GameMode.vsBot,
    this.botDifficulty    = BotDifficulty.hard,
    this.status           = GameStatus.waiting,
    this.twoDiceMode      = false,
    this.numPlayers       = 4,
    this.currentTurn      = 0,
    this.playerIndex      = 0,
    this.playerColorIndex = 0,
    this.playerDisplayName= 'You',
    this.playerNames      = const {},
    this.tokens           = const {},
    this.dice1            = 0,
    this.dice2            = 0,
    this.sixCount         = 0,
    this.extraTurn        = false,
    this.finishedPlayers  = const [],
    this.winner           = null,
    this.chatMessages     = const [],
    this.roomId           = null,
    this.userData         = null,
  });

  int  get totalDice  => twoDiceMode ? dice1 + dice2 : dice1;
  bool get diceRolled => totalDice > 0;
  bool get isPlayerTurn => currentTurn == playerIndex;
  bool get gameOver   => winner != null;

  List<int> get movable =>
      diceRolled && tokens.containsKey(currentTurn)
          ? movableTokens(currentTurn, tokens[currentTurn]!, totalDice)
          : [];

  GameState copyWith({
    GameMode?      mode,
    BotDifficulty? botDifficulty,
    GameStatus?    status,
    bool?          twoDiceMode,
    int?           numPlayers,
    int?           currentTurn,
    int?           playerIndex,
    int?           playerColorIndex,
    String?        playerDisplayName,
    Map<int, String>?            playerNames,
    Map<int, List<List<int>>>?   tokens,
    int?           dice1,
    int?           dice2,
    int?           sixCount,
    bool?          extraTurn,
    List<int>?     finishedPlayers,
    int?           winner,
    List<ChatMessage>? chatMessages,
    String?        roomId,
    UserData?      userData,
  }) => GameState(
    mode:              mode              ?? this.mode,
    botDifficulty:     botDifficulty     ?? this.botDifficulty,
    status:            status            ?? this.status,
    twoDiceMode:       twoDiceMode       ?? this.twoDiceMode,
    numPlayers:        numPlayers        ?? this.numPlayers,
    currentTurn:       currentTurn       ?? this.currentTurn,
    playerIndex:       playerIndex       ?? this.playerIndex,
    playerColorIndex:  playerColorIndex  ?? this.playerColorIndex,
    playerDisplayName: playerDisplayName ?? this.playerDisplayName,
    playerNames:       playerNames       ?? this.playerNames,
    tokens:            tokens            ?? this.tokens,
    dice1:             dice1             ?? this.dice1,
    dice2:             dice2             ?? this.dice2,
    sixCount:          sixCount          ?? this.sixCount,
    extraTurn:         extraTurn         ?? this.extraTurn,
    finishedPlayers:   finishedPlayers   ?? this.finishedPlayers,
    winner:            winner            ?? this.winner,
    chatMessages:      chatMessages      ?? this.chatMessages,
    roomId:            roomId            ?? this.roomId,
    userData:          userData          ?? this.userData,
  );
}

// ── User data ─────────────────────────────────────────────────────────────────
@immutable
class UserData {
  final String  uid;
  final String  email;
  final String  displayName;
  final int     coins;
  final int     wins;
  final int     losses;
  final int     games;
  final int     elo;
  final String? idToken;

  const UserData({
    required this.uid,
    required this.email,
    required this.displayName,
    this.coins   = 500,
    this.wins    = 0,
    this.losses  = 0,
    this.games   = 0,
    this.elo     = kDefaultElo,
    this.idToken,
  });

  UserData copyWith({
    int?    coins, int? wins, int? losses, int? games, int? elo,
    String? idToken, String? displayName,
  }) => UserData(
    uid: uid, email: email,
    displayName: displayName ?? this.displayName,
    coins:   coins   ?? this.coins,
    wins:    wins    ?? this.wins,
    losses:  losses  ?? this.losses,
    games:   games   ?? this.games,
    elo:     elo     ?? this.elo,
    idToken: idToken ?? this.idToken,
  );

  Map<String, dynamic> toJson() => {
    'uid': uid, 'email': email, 'displayName': displayName,
    'coins': coins, 'wins': wins, 'losses': losses,
    'games': games, 'elo': elo,
  };

  factory UserData.fromJson(Map<dynamic, dynamic> j, String uid,
      {String? idToken}) => UserData(
    uid:         uid,
    email:       j['email']       as String? ?? '',
    displayName: j['displayName'] as String? ??
                 j['email']       as String? ?? 'Player',
    coins:   (j['coins']  as num?)?.toInt() ?? 500,
    wins:    (j['wins']   as num?)?.toInt() ?? 0,
    losses:  (j['losses'] as num?)?.toInt() ?? 0,
    games:   (j['games']  as num?)?.toInt() ?? 0,
    elo:     (j['elo']    as num?)?.toInt() ?? kDefaultElo,
    idToken: idToken,
  );

  factory UserData.offline() => const UserData(
    uid: 'offline', email: 'offline@local', displayName: 'Player',
  );
}

// ── Chat ──────────────────────────────────────────────────────────────────────
@immutable
class ChatMessage {
  final String player;
  final String msg;
  final int    timestamp;

  const ChatMessage({
    required this.player,
    required this.msg,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() =>
      {'player': player, 'msg': msg, 'time': timestamp};

  factory ChatMessage.fromJson(Map<dynamic, dynamic> j) => ChatMessage(
    player:    j['player']    as String? ?? '',
    msg:       j['msg']       as String? ?? '',
    timestamp: (j['time'] as num?)?.toInt() ?? 0,
  );
}

// ── Bot AI ────────────────────────────────────────────────────────────────────
int botChooseToken({
  required int player,
  required List<List<int>> tokens,
  required int steps,
  required BotDifficulty difficulty,
  required Map<int, List<List<int>>> allTokens,
}) {
  final rng   = Random();
  final moves = movableTokens(player, tokens, steps);
  if (moves.isEmpty) return -1;
  if (difficulty == BotDifficulty.easy) return moves[rng.nextInt(moves.length)];

  int    bestToken = moves.first;
  double bestScore = -1;

  for (final ti in moves) {
    final newPos = calcNewPos(player, tokens, ti, steps);
    final npIdx  = pathIndex(player, newPos);
    double score = 0;

    for (final entry in allTokens.entries) {
      if (entry.key == player) continue;
      for (final tp in entry.value) {
        if (tp[0] == newPos[0] && tp[1] == newPos[1] && !isSafe(newPos)) {
          score += difficulty == BotDifficulty.hardest ? 300 : 150;
        }
      }
    }
    if (npIdx >= 100) score += difficulty == BotDifficulty.hardest ? 200 : 80;
    if (newPos[0] == kFinalHome[0] && newPos[1] == kFinalHome[1]) {
      score += difficulty == BotDifficulty.hardest ? 500 : 300;
    }
    final pidx = pathIndex(player, tokens[ti]);
    if (pidx == -1) score += difficulty == BotDifficulty.hardest ? 80 : 40;
    if (pidx >= 0 && pidx < 100) {
      score += difficulty == BotDifficulty.hardest ? pidx * 2 : pidx.toDouble();
    }
    if (difficulty == BotDifficulty.hardest) score += rng.nextInt(20);
    if (score > bestScore) { bestScore = score; bestToken = ti; }
  }
  return bestToken;
}
