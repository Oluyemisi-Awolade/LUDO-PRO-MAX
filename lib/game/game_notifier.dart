// lib/game/game_notifier.dart
import 'dart:async';
import 'dart:math';
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
  final _rng = Random();
  Timer? _pollTimer;
  bool _botRunning = false;
  bool _moveLock = false;

  AudioService get _audio => _ref.read(audioServiceProvider);
  FirebaseService get _fb => _ref.read(firebaseServiceProvider);

  // —— Setup ——
  void setupGame({
    required GameMode mode,
    BotDifficulty difficulty = BotDifficulty.hard,
    bool twoDice = false,
    int numPlayers = 4,
    int playerColor = 0,
  }) {
    _stopPoll();
    _botRunning = false;
    _moveLock = false;

    final n = mode == GameMode.vsBot ? 4 : numPlayers;

    // Build player names with human at chosen colour seat
    final Map<int, String> names = {};
    if (mode == GameMode.vsBot) {
      int botNum = 1;
      for (int i = 0; i < 4; i++) {
        if (i == playerColor) {
          names[i] = 'You';
        } else {
          names[i] = 'Bot $botNum';
          botNum++;
        }
      }
    } else {
      for (int i = 0; i < n; i++) {
        names[i] = i == playerColor ? 'You' : 'Player ${i + 1}';
      }
    }

    final tokens = {
      for (int i = 0; i < n; i++)
        i: kNestPositions[i].map((p) => List<int>.from(p)).toList(),
    };

    state = state.copyWith(
      mode: mode,
      botDifficulty: difficulty,
      twoDiceMode: twoDice,
      numPlayers: n,
      playerIndex: playerColor,
      playerColorIndex: playerColor,
      currentTurn: 0,
      playerNames: names,
      tokens: tokens,
      dice1: 0,
      dice2: 0,
      sixCount: 0,
      extraTurn: false,
      pendingDice: 0,
      finishedPlayers: [],
      winner: null,
      status: GameStatus.playing,
      chatMessages: [],
    );

    // FIX (#1): if the human didn't pick the colour that goes first,
    // currentTurn (0) belongs to a bot and nothing was kicking it off.
    if (mode == GameMode.vsBot && state.currentTurn != state.playerIndex) {
      _scheduleBotTurn();
    }
  }

  // —— Set player colour (online / picker) ——
  void setPlayerColor(int colorIndex, String displayName) {
    state = state.copyWith(
      playerIndex: colorIndex,
      playerColorIndex: colorIndex,
      playerDisplayName: displayName,
    );
    final ud = state.userData;
    if (ud != null) {
      state = state.copyWith(userData: ud.copyWith(displayName: displayName));
    }
  }

  // —— Roll dice ——
  Future<void> rollDice() async {
    if (_moveLock) return;

    final d1 = _rng.nextInt(6) + 1;
    final d2 = state.twoDiceMode ? _rng.nextInt(6) + 1 : 0;
    await _audio.play('dice');

    // Extra turn only on double-6 in two-dice mode, or a 6 in single-dice mode
    final isDouble = state.twoDiceMode ? (d1 == 6 && d2 == 6) : d1 == 6;
    int sixCount = state.sixCount;
    bool extra = false;

    if (isDouble) {
      await _audio.play('six');
      sixCount++;
      extra = true;
      if (sixCount >= 3) {
        // Three doubles/sixes — forfeit turn
        state = state.copyWith(
            dice1: d1, dice2: d2, sixCount: 0, extraTurn: false);
        await Future.delayed(const Duration(milliseconds: 800));
        state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
        await _advanceTurn();
        return;
      }
    } else {
      sixCount = 0;
      extra = false; // always reset extra when no double/six
    }

    state = state.copyWith(
      dice1: d1,
      dice2: d2,
      sixCount: sixCount,
      extraTurn: extra,
      pendingDice: 0,
    );
    await _syncRoom();

    final playerTokens = state.tokens[state.playerIndex];
    if (playerTokens == null) return;

    // A move is possible this turn if EITHER die can move something
    final movesD1 = state.dice1 > 0
        ? movableTokens(state.playerIndex, playerTokens, d1)
        : <int>[];
    final movesD2 = (state.twoDiceMode && state.dice2 > 0)
        ? movableTokens(state.playerIndex, playerTokens, d2)
        : <int>[];

    if (movesD1.isEmpty && movesD2.isEmpty) {
      await _audio.play('invalid');
      await Future.delayed(const Duration(milliseconds: 1000));
      state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
      if (!extra) {
        await _advanceTurn();
      } else {
        state = state.copyWith(extraTurn: false);
      }
    }
  }

  // —— Move token ——
  // dieChoice: 1 = use dice1's value, 2 = use dice2's value (twoDiceMode only)
  Future<bool> moveToken(int player, int tokenIdx, {int dieChoice = 1}) async {
    if (_moveLock) return false;
    _moveLock = true;
    try {
      return await _doMove(player, tokenIdx, dieChoice: dieChoice);
    } finally {
      _moveLock = false;
    }
  }

  Future<bool> _doMove(int player, int tokenIdx, {int dieChoice = 1}) async {
    final d1 = state.dice1;
    final d2 = state.dice2;
    final steps = (dieChoice == 2 && state.twoDiceMode) ? d2 : d1;
    if (steps == 0) return false;

    final tokens = Map<int, List<List<int>>>.from(
      state.tokens.map(
          (k, v) => MapEntry(k, v.map((p) => List<int>.from(p)).toList())),
    );

    if (!canMove(player, tokens[player]!, tokenIdx, steps)) return false;

    final newPos = calcNewPos(player, tokens[player]!, tokenIdx, steps);
    bool captured = false;

    // Capture check
    if (!isSafe(newPos) &&
        !(newPos[0] == kFinalHome[0] && newPos[1] == kFinalHome[1])) {
      for (final entry in tokens.entries) {
        if (entry.key == player) continue;
        for (int ti = 0; ti < entry.value.length; ti++) {
          final tp = entry.value[ti];
          if (tp[0] == newPos[0] && tp[1] == newPos[1] && !isSafe(tp)) {
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

    // Which die(s), if any, are still unplayed after this move
    final remainingD1 = dieChoice == 1 ? 0 : d1;
    final remainingD2 = (dieChoice == 2 && state.twoDiceMode) ? 0 : d2;

    List<int> finished = List<int>.from(state.finishedPlayers);
    int? winner = state.winner;

    if (allHome(tokens[player]!)) {
      if (!finished.contains(player)) finished.add(player);

      if (state.mode == GameMode.vsBot) {
        // Single-player vs bots: first to finish all 4 tokens wins
        // immediately — the game ends right here.
        winner = player;

        if (player == state.playerIndex) {
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              wins: ud.wins + 1,
              coins: ud.coins + kPlaceRewards[0],
              games: ud.games + 1,
              elo: newElo(ud.elo, kDefaultElo, won: true),
            );
            state = state.copyWith(userData: updated);
            _fb.saveUser(updated);
          }
          await _audio.play('win');
        } else {
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              losses: ud.losses + 1,
              elo: newElo(ud.elo, kDefaultElo, won: false),
            );
            state = state.copyWith(userData: updated);
            _fb.saveUser(updated);
          }
        }
      } else {
        // Local or online multiplayer: play out full placements —
        // the game only ends once a single player is left unfinished.
        if (player == state.playerIndex) {
          final place = finished.indexOf(player);
          final reward = kPlaceRewards[place.clamp(0, 3)];
          final ud = state.userData;
          if (ud != null) {
            final updated = ud.copyWith(
              wins: ud.wins + 1,
              coins: ud.coins + reward,
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
                elo: newElo(ud.elo, kDefaultElo, won: false),
              );
              state = state.copyWith(userData: updated);
              _fb.saveUser(updated);
            }
          }
          winner = finished.isNotEmpty ? finished.first : player;
        }
      }
    }

    // FIX (#4/#5): only the used die is cleared. If the other die is
    // still unplayed (two-dice mode), the SAME turn continues so it can
    // be applied to a different token, instead of being discarded.
    final stillHasDie =
        (remainingD1 > 0) || (state.twoDiceMode && remainingD2 > 0);

    if (stillHasDie && winner == null) {
      state = state.copyWith(
        tokens: tokens,
        dice1: remainingD1,
        dice2: remainingD2,
        finishedPlayers: finished,
        winner: winner,
        extraTurn: state.extraTurn || captured,
      );
      await _syncRoom();

      final movesLeft = movableTokens(
        player,
        tokens[player]!,
        remainingD1 > 0 ? remainingD1 : remainingD2,
      );
      if (movesLeft.isEmpty) {
        // Remaining die can't be used by anything — forfeit just that die
        final extra = state.extraTurn;
        state = state.copyWith(dice1: 0, dice2: 0, pendingDice: 0);
        if (!extra) {
          await _advanceTurn();
        } else {
          state = state.copyWith(extraTurn: false);
          if (state.mode != GameMode.online) _scheduleBotTurn();
        }
      }
      return true;
    }

    // Both dice used (or single-die mode) — finish the turn
    final extra = state.extraTurn || captured;
    state = state.copyWith(
      tokens: tokens,
      dice1: 0,
      dice2: 0,
      pendingDice: 0,
      finishedPlayers: finished,
      winner: winner,
      extraTurn: extra,
    );
    await _syncRoom();

    if (winner == null) {
      if (!extra) {
        await _advanceTurn();
      } else {
        // Extra turn — same player, clear flag so they roll again
        state = state.copyWith(extraTurn: false);
        if (state.mode != GameMode.online) _scheduleBotTurn();
      }
    }
    return true;
  }

  // —— Turn management ——
  Future<void> _advanceTurn() async {
    if (state.gameOver) return;
    int nxt = (state.currentTurn + 1) % state.numPlayers;
    int loops = 0;
    while (state.finishedPlayers.contains(nxt) && loops < state.numPlayers) {
      nxt = (nxt + 1) % state.numPlayers;
      loops++;
    }
    state = state.copyWith(
      currentTurn: nxt,
      dice1: 0,
      dice2: 0,
      pendingDice: 0,
      extraTurn: false,
      sixCount: 0,
    );
    if (state.mode != GameMode.online) _scheduleBotTurn();
  }

  void _scheduleBotTurn() {
    if (_botRunning) return;
    if (state.gameOver) return;
    if (state.mode == GameMode.localMultiplayer) return;
    if (state.currentTurn == state.playerIndex) return;
    Future.delayed(const Duration(milliseconds: 1000), _runBot);
  }

  // FIX (#3): the bot now runs the same doubles/six extra-turn detection
  // as the human path (rollDice), and plays each die as its own move
  // instead of always moving one token by the summed total.
  Future<void> _runBot() async {
    if (_botRunning || state.gameOver) return;
    if (state.mode == GameMode.localMultiplayer) return;
    if (state.currentTurn == state.playerIndex) return;
    _botRunning = true;
    try {
      final bot = state.currentTurn;
      final d1 = _rng.nextInt(6) + 1;
      final d2 = state.twoDiceMode ? _rng.nextInt(6) + 1 : 0;
      await _audio.play('dice');

      final isDouble =
          state.twoDiceMode ? (d1 == 6 && d2 == 6) : d1 == 6;
      int sixCount = state.sixCount;
      bool extra = false;

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
        extra = false;
      }

      state = state.copyWith(
        dice1: d1,
        dice2: d2,
        sixCount: sixCount,
        extraTurn: extra,
      );
      await Future.delayed(const Duration(milliseconds: 700));
      if (state.gameOver || state.currentTurn != bot) return;

      await _botPlayDie(bot, 1);
      if (state.gameOver || state.currentTurn != bot) return;

      if (state.twoDiceMode && state.dice2 > 0 && state.currentTurn == bot) {
        await _botPlayDie(bot, 2);
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

  Future<void> _botPlayDie(int bot, int dieChoice) async {
    final dieVal = dieChoice == 1 ? state.dice1 : state.dice2;
    if (dieVal == 0) return;

    final ti = botChooseToken(
      player: bot,
      tokens: state.tokens[bot]!,
      steps: dieVal,
      difficulty: state.botDifficulty,
      allTokens: state.tokens,
      dice1: state.dice1,
      dice2: state.dice2,
    );

    if (ti == -1) {
      state =
          dieChoice == 1 ? state.copyWith(dice1: 0) : state.copyWith(dice2: 0);

      if (state.dice1 == 0 && (!state.twoDiceMode || state.dice2 == 0)) {
        final extra = state.extraTurn;
        state = state.copyWith(pendingDice: 0);
        if (!extra) {
          await _advanceTurn();
        } else {
          state = state.copyWith(extraTurn: false);
        }
      }
    } else {
      await _doMove(bot, ti, dieChoice: dieChoice);
    }
  }

  // —— Online ——
  Future<String> createRoom({bool twoDice = false}) async {
    final code = (100000 + _rng.nextInt(899999)).toString();
    final ud = state.userData!;
    await _fb.putRoom(
        code,
        {
          'players': {'0': ud.displayName},
          'colors': {'0': state.playerColorIndex},
          'tokens': {
            '0': kNestPositions[state.playerColorIndex]
                .map((p) => List<int>.from(p))
                .toList(),
          },
          'current_turn': 0,
          'dice1': 0,
          'dice2': 0,
          'winner': null,
          'state': 'waiting',
          'two_dice_mode': twoDice,
          'finished_players': [],
          'chat': {},
        },
        ud.idToken ?? '');

    state = state.copyWith(
      roomId: code,
      playerIndex: state.playerColorIndex,
      mode: GameMode.online,
      twoDiceMode: twoDice,
      status: GameStatus.waiting,
      tokens: {
        state.playerColorIndex: kNestPositions[state.playerColorIndex]
            .map((p) => List<int>.from(p))
            .toList(),
      },
      playerNames: {state.playerColorIndex: ud.displayName},
    );
    _startPoll();
    return code;
  }

  Future<(bool, String)> joinRoom(String code) async {
    final ud = state.userData!;
    final room = await _fb.getRoom(code, ud.idToken ?? '');
    if (room == null) return (false, 'Room not found');
    final players = Map<String, dynamic>.from(room['players'] as Map? ?? {});
    final colors = Map<String, dynamic>.from(room['colors'] as Map? ?? {});
    if (colors.values.contains(state.playerColorIndex)) {
      return (
        false,
        'Colour ${kPlayerNames[state.playerColorIndex]} is taken'
      );
    }
    if (players.length >= 4) return (false, 'Room is full');
    final myColor = state.playerColorIndex.toString();
    players[myColor] = ud.displayName;
    colors[myColor] = state.playerColorIndex;
    final tokens = Map<String, dynamic>.from(room['tokens'] as Map? ?? {});
    tokens[myColor] = kNestPositions[state.playerColorIndex]
        .map((p) => List<int>.from(p))
        .toList();
    final newState = players.length == 4 ? 'playing' : 'waiting';
    await _fb.patchRoom(
        code,
        {
          'players': players,
          'colors': colors,
          'tokens': tokens,
          'state': newState,
        },
        ud.idToken ?? '');
    final pMap = {
      for (final e in players.entries) int.parse(e.key): e.value as String,
    };
    final tMap = {
      for (final e in tokens.entries)
        int.parse(e.key):
            (e.value as List).map((r) => List<int>.from(r as List)).toList(),
    };
    state = state.copyWith(
      roomId: code,
      playerIndex: state.playerColorIndex,
      mode: GameMode.online,
      twoDiceMode: room['two_dice_mode'] as bool? ?? false,
      playerNames: pMap,
      tokens: tMap,
      status:
          newState == 'playing' ? GameStatus.playing : GameStatus.waiting,
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
        .map((e) => e as int)
        .toList();
    final chats = <ChatMessage>[];
    final rawChat = room['chat'] as Map?;
    if (rawChat != null) {
      final sorted = rawChat.values
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      chats.addAll(sorted);
    }
    state = state.copyWith(
      tokens: tokens,
      currentTurn:
          (room['current_turn'] as num?)?.toInt() ?? state.currentTurn,
      dice1: (room['dice1'] as num?)?.toInt() ?? 0,
      dice2: (room['dice2'] as num?)?.toInt() ?? 0,
      winner: room['winner'] as int?,
      playerNames: players,
      finishedPlayers: finished,
      chatMessages: chats,
      status:
          room['state'] == 'playing' ? GameStatus.playing : GameStatus.waiting,
    );
  }

  Future<void> _syncRoom() async {
    if (state.mode != GameMode.online || state.roomId == null) return;
    final tok = {
      for (final e in state.tokens.entries) e.key.toString(): e.value
    };
    await _fb.patchRoom(
        state.roomId!,
        {
          'tokens': tok,
          'current_turn': state.currentTurn,
          'dice1': state.dice1,
          'dice2': state.dice2,
          'winner': state.winner,
          'finished_players': state.finishedPlayers,
        },
        state.userData!.idToken!);
  }

  Future<void> sendChat(String msg) async {
    if (msg.trim().isEmpty) return;
    final entry = ChatMessage(
      player: kPlayerNames[state.playerIndex],
      msg: msg.trim(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    if (state.mode == GameMode.online && state.roomId != null) {
      await _fb.patchRoom(
          state.roomId!,
          {'chat/${entry.timestamp}': entry.toJson()},
          state.userData!.idToken!);
    } else {
      state = state.copyWith(chatMessages: [...state.chatMessages, entry]);
    }
  }

  void setUser(UserData ud) => state = state.copyWith(userData: ud);
  void clearUser() => state = state.copyWith(userData: null);

  @override
  void dispose() {
    _stopPoll();
    super.dispose();
  }
}
