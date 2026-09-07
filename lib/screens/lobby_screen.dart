// lib/screens/lobby_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../game/game_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'game_screen.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({super.key});

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading   = false;
  String? _myCode;

  // FEATURE (online player count): mirrors the 2P/3P/4P choice already on
  // the Local Play screen. Defaults to 4 so behavior for anyone who never
  // touches the picker matches the old hardcoded "always a 4-player room".
  int _numPlayers = 4;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom({bool twoDice = false}) async {
    setState(() => _loading = true);
    try {
      final code = await ref
          .read(gameProvider.notifier)
          .createRoom(twoDice: twoDice, numPlayers: _numPlayers);
      setState(() => _myCode = code);
    } catch (e) {
      if (mounted) showSnack(context, 'Error: $e', color: Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      showSnack(context, 'Enter a room code', color: Colors.orange.shade700);
      return;
    }
    setState(() => _loading = true);
    // FIX: joinRoom() reads room data from Firebase and parses several
    // maps out of it (players/colors/tokens). Any unexpected shape or
    // network hiccup there throws — previously that exception had
    // nothing catching it here, so it propagated up silently: the
    // `finally` below still ran (button re-enabled, loading spinner
    // gone) but the user never saw why the join didn't happen. Now any
    // such error surfaces as a SnackBar instead of a silent reset.
    try {
      final (ok, msg) = await ref.read(gameProvider.notifier).joinRoom(code);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const GameScreen()),
        );
      } else {
        showSnack(context, msg, color: Colors.red.shade700);
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Could not join room: $e', color: Colors.red.shade700);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gs = ref.watch(gameProvider);

    // FEATURE (online player count): was "Auto-navigate once room hits 4
    // players and state becomes playing" — the room's start threshold is
    // now whatever the creator picked (2/3/4), not always 4, so this
    // navigates whenever the notifier flips status to playing, whatever
    // that target was. See game_notifier.dart joinRoom()/_pollRoom().
    if (gs.status.name == 'playing' && _myCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const GameScreen()),
          );
        }
      });
    }

        return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Online Lobby',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Create room ──────────────────────────────────────────
                    _SectionCard(
                      title: 'Create a Room',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Share your room code with friends so they can join.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 14),

                          // FEATURE (online player count): 2P/3P/4P picker,
                          // same shape as Local Play. Locked once a room
                          // code has been generated — capacity is fixed
                          // server-side in max_players at creation time, so
                          // changing it after the fact wouldn't do anything.
                          _PlayerCountPicker(
                            value: _numPlayers,
                            enabled: !_loading && _myCode == null,
                            onChanged: (n) => setState(() => _numPlayers = n),
                          ),
                          const SizedBox(height: 14),

                          ElevatedButton.icon(
                            onPressed: _loading ? null : () => _createRoom(twoDice: false),
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                            label: const Text('Create Room  (1 Dice)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _loading ? null : () => _createRoom(twoDice: true),
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                            label: const Text('Create Room  (2 Dice 🎲🎲)'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),

                          // Show generated code
                          if (_myCode != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.violet),
                              ),
                              child: Column(
                                children: [
                                  Text('Your Room Code',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(color: Colors.white38)),
                                  const SizedBox(height: 6),
                                  Text(
                                    _myCode!,
                                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                          color: AppColors.violetLit,
                                          letterSpacing: 6,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _myCode!));
                                      showSnack(context, 'Code copied!');
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 15),
                                    label: const Text('Copy Code'),
                                    style: TextButton.styleFrom(
                                        foregroundColor: Colors.white54),
                                  ),
                                  const SizedBox(height: 4),
                                  // FEATURE (online player count): shows the
                                  // live joined count against the target the
                                  // creator picked. gs.numPlayers is kept in
                                  // sync by _pollRoom() as people join.
                                  _WaitingIndicator(
                                    joined: gs.numPlayers,
                                    target: _numPlayers,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const LabelDivider('OR JOIN AN EXISTING ROOM'),
                    const SizedBox(height: 16),

                    // ── Join room ────────────────────────────────────────────
                    _SectionCard(
                      title: 'Join a Room',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _codeCtrl,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6,
                            ),
                            decoration: const InputDecoration(
                              hintText: '000000',
                              counterText: '',
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _loading ? null : _joinRoom,
                            icon: const Icon(Icons.login_rounded, size: 17),
                            label: const Text('Join Room'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_loading) ...[
                      const SizedBox(height: 24),
                      const Center(
                        child: CircularProgressIndicator(color: AppColors.violet),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// FEATURE (online player count): same visual pattern as the Local Play
// 2P/3P/4P pills — a row of three equal, tappable, rounded chips, the
// selected one filled and the others dimmed. Colors approximate the
// blue/teal/indigo used on Local Play; swap in your exact AppColors
// tokens here if Local Play's picker exposes them as constants.
class _PlayerCountPicker extends StatelessWidget {
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _PlayerCountPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const _options = <int, Color>{
    2: Color(0xFF2D82D9), // blue
    3: Color(0xFF0F9D77), // teal/green
    4: Color(0xFF4C4FCE), // indigo
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in _options.entries) ...[
          if (entry.key != _options.keys.first) const SizedBox(width: 10),
          Expanded(
            child: _PlayerCountChip(
              label: '${entry.key}P',
              color: entry.value,
              selected: value == entry.key,
              enabled: enabled,
              onTap: () => onChanged(entry.key),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerCountChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PlayerCountChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: selected ? color : color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : color.withOpacity(0.4),
                width: selected ? 0 : 1,
              ),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingIndicator extends StatelessWidget {
  final int joined;
  final int target;
  const _WaitingIndicator({required this.joined, required this.target});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.violetLit),
        ),
        const SizedBox(width: 8),
        Text('Waiting for players… ($joined/$target)',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.white38)),
      ],
    );
  }
}
