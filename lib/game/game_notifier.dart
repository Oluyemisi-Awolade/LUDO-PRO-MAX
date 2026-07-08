// lib/game/game_notifier.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';
import '../core/board_logic.dart';
import '../services/firebase_service.dart';
import '../services/audio_service.dart';
import 'game_state.dart';

final gameProvider = StateNotifierProvider<GameNotifier, GameState>(
  (ref) => GameNotifier(ref),
);

class GameNotifier extends StateNotifier<GameState> {
  GameNotifier(this._ref) : super(const GameState());

  final Ref _ref;
  final _rng  = Random();
  Timer? _pollTimer;
  bool _botRunning = false;
  bool _moveLock   = false;

  AudioService    get _audio => _ref.read(audioServiceProvider);
  FirebaseService get _fb    => _ref.read(firebaseServiceProvider);

  // ── Setup ──────────────────────────────────────────────────────────────────
  void setupGame({
    required GameMode mode,
    BotDifficulty difficulty = BotDifficulty.hard,
    bool twoDice    = true,
    int  numPlayers = 4,
    int  playerColor = 0,   // chosen colour seat
  }) {
    _stopPoll();
    _botRunning = false;
    _moveLock   = false;

    final names = mode == GameMode.vsBot
        ? {
            playerColor: 'You',
            for (int i = 0; i < 4; i++)
              if (i != playerColor) i: 'Bot ${i + 1}',
          }
        : {for (int i = 0; i < numPlayers; i++) i: 'Player ${i + 1}'};

    final n = mode == GameMode.vsBot ? 4 : numPlayers;
    final tokens = {
      for (int i = 0; i < n; i++)
        i: kNestPositions[i].map((p) => List<int>.from(p)).toList(),
    };

    state = state.copyWith(
      mode:             mode,
      botDifficulty:    difficulty,
      twoDiceMode:      true,
      numPlayers:       n,
      playerIndex:      playerColor,
      playerColorIndex: playerColor,
      currentTurn:      0,
      playerNames:      names,
      tokens:           tokens,
      dice1:            0,
      dice2:            0,
      sixCount:         0,
      extraTurn:        false,
      pendingDice:      0,   // leftover die after using one
      finishedPlayers:  [],
      winner:           null,
      status:           GameStatus.playing,
      chatMessages:     [],
    );
  }

  // ── Player colour / name ───────────────────────────────────────────────────
  void setPlayerColor(int colorIndex, String displayName) {
    state = state.copyWith(
      playerIndex:       colorIndex,
      playerColorIndex:  colorIndex,
      playerDisplayName: displayName,
    );
    final ud = state.userData;
    if (ud != null) {
      state = state.copyWith(
          userData: ud.copyWith(displayName: displayName));
    }
  }

  // ── Dice roll ──────────────────────────────────────────────────────────────
  // Two-dice rule:
  // - Roll both dice
  // - If one is 6: token comes out using the 6, then the other die value
  //   is stored as pendingDice so player can use it for another move
  // - If doubles: extra turn
  // - Otherwise: total = d1+d2, move one token that total
  Future<void> rollDice() async {
    if (!state.isPlayerTurn) return;
    if (state.diceRolled)    return;
    if (state.gameOver)      return;
    if (_moveLock)           return;

    final d1    = _rng.nextInt(6) + 1;
    final d2    = _rng.nextInt(6) + 1;
    await _audio.play('dice');

    final isDouble = d1 == d2;
    final hasSix   = d1 == 6 || d2 == 6;
    int  sixCount  = state.sixCount;
    bool extra     = false;

    if (isDouble) {
      await _audio.play('six');
      sixCount++;
      extra = true;
      if (sixCount >= 3) {
        state = state.copyWith(
            dice1: d1, dice2: d2, sixCount: 0, extraTurn: false);
        await Future.delayed(const Duration(milliseconds: 800));
        state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
        await _advanceTurn();
        return;
      }
    } else {
      sixCount = 0;
      extra    = false;
    }

    final total = d1 + d2;

    state = state.copyWith(
      dice1:       d1,
      dice2:       d2,
      sixCount:    sixCount,
      extraTurn:   extra,
      pendingDice: 0,
    );
    await _syncRoom();

    // Check movable tokens
    final playerTokens = state.tokens[state.playerIndex];
    if (playerTokens == null) return;

    final moves = movableTokens(
      state.playerIndex, playerTokens, total,
      dice1: d1, dice2: d2,
    );

    if (moves.isEmpty) {
      await _audio.play('invalid');
      await Future.delayed(const Duration(milliseconds: 1000));
      state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
      if (!extra) await _advanceTurn();
      else state = state.copyWith(extraTurn: false);
    }
  }

  // ── Move token ─────────────────────────────────────────────────────────────
  Future<bool> moveToken(int player, int tokenIdx) async {
    if (_moveLock) return false;
    _moveLock = true;
    try {
      return await _doMove(player, tokenIdx);
    } finally {
      _moveLock = false;
    }
  }

  Future<bool> _doMove(int player, int tokenIdx) async {
    final d1    = state.dice1;
    final d2    = state.dice2;
    final total = state.totalDice;
    if (total == 0) return false;

    final tokens = Map<int, List<List<int>>>.from(
      state.tokens.map((k, v) =>
          MapEntry(k, v.map((p) => List<int>.from(p)).toList())),
    );

    final currentPos = tokens[player]![tokenIdx];
    final pidx = pathIndex(player, currentPos);
    final inNest = pidx == -1;

    // Determine which die value to use
    // If token is in nest, must use the 6
    // If both dice available, use total
    int stepsUsed = total;
    int leftover  = 0;

    if (inNest) {
      // Use the 6 to come out, leftover = the other die
      if (d1 == 6 && d2 != 6) {
        stepsUsed = 6;
        leftover  = d2;
      } else if (d2 == 6 && d1 != 6) {
        stepsUsed = 6;
        leftover  = d1;
      } else {
        // Both are 6 (doubles) — use 6 to come out, 6 again as leftover
        stepsUsed = 6;
        leftover  = 6;
      }
    }

    if (!canMove(player, tokens[player]!, tokenIdx, stepsUsed,
        dice1: d1, dice2: d2)) return false;

    final newPos  = calcNewPos(player, tokens[player]!, tokenIdx, stepsUsed);
    bool captured = false;

    // Capture check
    if (!isSafe(newPos) &&
        !(newPos[0] == kFinalHome[0] && newPos[1] == kFinalHome[1])) {
      for (final entry in tokens.entries) {
        if (entry.key == player) continue;
        for (int ti = 0; ti < entry.value.length; ti++) {
          final tp = entry.value[ti];
          if (tp[0] == newPos[0] &&
              tp[1] == newPos[1] &&
              !isSafe(tp)) {
            tokens[entry.key]![ti] =
                List<int>.from(kNestPositions[entry.key][ti]);
            captured = true;
          }
        }
      }
    }
    if (captured) await _audio.play('capture');

    tokens[player]![tokenIdx] = newPos;
    await _audio.play('move');

    bool      extra    = state.extraTurn || captured;
    List<int> finished = List<int>.from(state.finishedPlayers);
    int?      winner   = state.winner;

    if (allHome(tokens[player]!)) {
      if (!finished.contains(player)) finished.add(player);
      if (player == state.playerIndex) {
        final place  = finished.indexOf(player);
        final reward = kPlaceRewards[place.clamp(0, 3)];
        final ud     = state.userData;
        if (ud != null) {
          final updated = ud.copyWith(
            wins: ud.wins + 1, coins: ud.coins + reward,
            games: ud.games + 1,
            elo: newElo(ud.elo, kDefaultElo, won: true),
          );
          state = state.copyWith(userData: updated);
          _fb.saveUser(updated);
        }
        await _audio.play('win');
      }
      final remaining = [
        for (int i = 0; i < state.numPlayers; i++)
          if (!finished.contains(i)) i,
      ];
      if (remaining.length <= 1) {
        if (remaining.isNotEmpty &&
            remaining.first == state.playerIndex &&
            !finished.contains(state.playerIndex)) {
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              losses: ud.losses + 1,
              elo:    newElo(ud.elo, kDefaultElo, won: false),
            );
            state = state.copyWith(userData: updated);
            _fb.saveUser(updated);
          }
        }
        winner = finished.isNotEmpty ? finished.first : player;
        extra  = false;
        leftover = 0;
      }
    }

    // If leftover die (e.g. rolled 6,4 and used 6 to exit nest)
    // store leftover so player can make a second move
    if (leftover > 0 && winner == null) {
      state = state.copyWith(
        tokens:          tokens,
        dice1:           leftover,
        dice2:           0,
        finishedPlayers: finished,
        winner:          winner,
        extraTurn:       true,
        pendingDice:     leftover,
      );
      await _syncRoom();
      // Check if leftover move is possible
      final movesLeft = movableTokens(
        player, tokens[player]!, leftover,
        dice1: leftover, dice2: 0,
      );
      if (movesLeft.isEmpty) {
        // No moves with leftover — clear and advance
        state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
        await _advanceTurn();
      }
      return true;
    }

    // Normal: reset dice
    state = state.copyWith(
      tokens:          tokens,
      dice1:           0,
      dice2:           0,
      pendingDice:     0,
      finishedPlayers: finished,
      winner:          winner,
      extraTurn:       extra,
    );

    await _syncRoom();

    if (winner == null) {
      if (!extra) {
        await _advanceTurn();
      } else {
        state = state.copyWith(extraTurn: false);
        if (state.mode != GameMode.online) _scheduleBotTurn();
      }
    }
    return true;
  }

  // ── Turn management ────────────────────────────────────────────────────────
  Future<void> _advanceTurn() async {
    if (state.gameOver) return;
    int nxt   = (state.currentTurn + 1) % state.numPlayers;
    int loops = 0;
    while (state.finishedPlayers.contains(nxt) &&
        loops < state.numPlayers) {
      nxt = (nxt + 1) % state.numPlayers;
      loops++;
    }
    state = state.copyWith(
      currentTurn: nxt,
      dice1: 0, dice2: 0,
      pendingDice: 0,
      extraTurn:   false,
      sixCount:    0,
    );
    if (state.mode != GameMode.online) _scheduleBotTurn();
  }

  void _scheduleBotTurn() {
    if (_botRunning)                             return;
    if (state.gameOver)                          return;
    if (state.mode == GameMode.localMultiplayer) return;
    if (state.currentTurn == state.playerIndex)  return;
    Future.delayed(const Duration(milliseconds: 1000), _runBot);
  }

  Future<void> _runBot() async {
    if (_botRunning || state.gameOver)           return;
    if (state.mode == GameMode.localMultiplayer) return;
    if (state.currentTurn == state.playerIndex)  return;
    _botRunning = true;
    try {
      final bot = state.currentTurn;
      final d1  = _rng.nextInt(6) + 1;
      final d2  = _rng.nextInt(6) + 1;
      final total = d1 + d2;

      state = state.copyWith(dice1: d1, dice2: d2);
      await _audio.play('dice');
      await Future.delayed(const Duration(milliseconds: 700));

      if (state.gameOver || state.currentTurn != bot) return;

      final ti = botChooseToken(
        player:     bot,
        tokens:     state.tokens[bot]!,
        steps:      total,
        difficulty: state.botDifficulty,
        allTokens:  state.tokens,
        dice1:      d1,
        dice2:      d2,
      );

      if (ti == -1) {
        state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
        await _advanceTurn();
      } else {
        await _doMove(bot, ti);
      }
    } finally {
      _botRunning = false;
      if (!state.gameOver &&
          state.currentTurn != state.playerIndex &&
          state.mode != GameMode.localMultiplayer) {
        Future.delayed(const Duration(milliseconds: 800), _runBot);
      }
    }
  }

  // ── Online ─────────────────────────────────────────────────────────────────
  Future<String> createRoom({bool twoDice = true}) async {
    final code = (100000 + _rng.nextInt(899999)).toString();
    final ud   = state.userData!;
    await _fb.putRoom(code, {
      'players': {'0': ud.displayName},
      'colors':  {'0': state.playerColorIndex},
      'tokens': {
        '0': kNestPositions[state.playerColorIndex]
            .map((p) => List<int>.from(p)).toList(),
      },
      'current_turn': 0,
      'dice1': 0, 'dice2': 0,
      'winner': null,
      'state': 'waiting',
      'two_dice_mode': true,
      'finished_players': [],
      'chat': {},
    }, ud.idToken ?? '');

    state = state.copyWith(
      roomId: code, playerIndex: state.playerColorIndex,
      mode: GameMode.online, twoDiceMode: true,
      status: GameStatus.waiting,
      tokens: {
        state.playerColorIndex: kNestPositions[state.playerColorIndex]
            .map((p) => List<int>.from(p)).toList(),
      },
      playerNames: {state.playerColorIndex: ud.displayName},
    );
    _startPoll();
    return code;
  }

  Future<(bool, String)> joinRoom(String code) async {
    final ud   = state.userData!;
    final room = await _fb.getRoom(code, ud.idToken ?? '');
    if (room == null) return (false, 'Room not found');
    final players = Map<String, dynamic>.from(room['players'] as Map? ?? {});
    final colors  = Map<String, dynamic>.from(room['colors']  as Map? ?? {});
    if (colors.values.contains(state.playerColorIndex)) {
      return (false,
          'Colour ${kPlayerNames[state.playerColorIndex]} is taken');
    }
    if (players.length >= 4) return (false, 'Room is full');
    final myColor = state.playerColorIndex.toString();
    players[myColor] = ud.displayName;
    colors[myColor]  = state.playerColorIndex;
    final tokens = Map<String, dynamic>.from(room['tokens'] as Map? ?? {});
    tokens[myColor] = kNestPositions[state.playerColorIndex]
        .map((p) => List<int>.from(p)).toList();
    final newState = players.length == 4 ? 'playing' : 'waiting';
    await _fb.patchRoom(code,
        {'players': players, 'colors': colors,
         'tokens': tokens, 'state': newState},
        ud.idToken ?? '');
    final pMap = {
      for (final e in players.entries) int.parse(e.key): e.value as String,
    };
    final tMap = {
      for (final e in tokens.entries)
        int.parse(e.key): (e.value as List)
            .map((r) => List<int>.from(r as List)).toList(),
    };
    state = state.copyWith(
      roomId: code, playerIndex: state.playerColorIndex,
      mode: GameMode.online, twoDiceMode: true,
      playerNames: pMap, tokens: tMap,
      status: newState == 'playing'
          ? GameStatus.playing : GameStatus.waiting,
    );
    _startPoll();
    return (true, 'Joined!');
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1500), (_) => _pollRoom());
  }

  void _stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollRoom() async {
    if (state.roomId == null || state.userData?.idToken == null) return;
    final room = await _fb.getRoom(state.roomId!, state.userData!.idToken!);
    if (room == null) return;
    final tokens = <int, List<List<int>>>{};
    final rawT = room['tokens'] as Map?;
    if (rawT != null) {
      for (final e in rawT.entries) {
        tokens[int.parse(e.key.toString())] =
            (e.value as List).map((r) => List<int>.from(r as List)).toList();
      }
    }
    final players = <int, String>{};
    final rawP = room['players'] as Map?;
    if (rawP != null) {
      for (final e in rawP.entries) {
        players[int.parse(e.key.toString())] = e.value.toString();
      }
    }
    final finished = ((room['finished_players'] as List?) ?? [])
        .map((e) => e as int).toList();
    final chats = <ChatMessage>[];
    final rawChat = room['chat'] as Map?;
    if (rawChat != null) {
      final sorted = rawChat.values
          .map((e) => ChatMessage.fromJson(e as Map)).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      chats.addAll(sorted);
    }
    state = state.copyWith(
      tokens: tokens,
      currentTurn: (room['current_turn'] as num?)?.toInt() ?? state.currentTurn,
      dice1: (room['dice1'] as num?)?.toInt() ?? 0,
      dice2: (room['dice2'] as num?)?.toInt() ?? 0,
      winner: room['winner'] as int?,
      playerNames: players,
      finishedPlayers: finished,
      chatMessages: chats,
      status: room['state'] == 'playing'
          ? GameStatus.playing : GameStatus.waiting,
    );
  }

  Future<void> _syncRoom() async {
    if (state.mode != GameMode.online || state.roomId == null) return;
    final tok = {
      for (final e in state.tokens.entries) e.key.toString(): e.value,
    };
    await _fb.patchRoom(state.roomId!, {
      'tokens': tok,
      'current_turn': state.currentTurn,
      'dice1': state.dice1, 'dice2': state.dice2,
      'winner': state.winner,
      'finished_players': state.finishedPlayers,
    }, state.userData!.idToken!);
  }

  Future<void> sendChat(String msg) async {
    if (msg.trim().isEmpty) return;
    final entry = ChatMessage(
      player:    kPlayerNames[state.playerIndex],
      msg:       msg.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    if (state.mode == GameMode.online && state.roomId != null) {
      await _fb.patchRoom(state.roomId!,
          {'chat/${entry.timestamp}': entry.toJson()},
          state.userData!.idToken!);
    } else {
      state = state.copyWith(chatMessages: [...state.chatMessages, entry]);
    }
  }

  void setUser(UserData ud)  => state = state.copyWith(userData: ud);
  void clearUser()           => state = state.copyWith(userData: null);

  @override
  void dispose() {
    _stopPoll();
    super.dispose();
  }
}
