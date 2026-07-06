// lib/screens/avatar_picker_screen.dart
// Shown before entering/creating an online room.
// Player picks their colour token, then proceeds to lobby.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants.dart';
import '../game/game_notifier.dart';
import '../game/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import 'lobby_screen.dart';

class AvatarPickerScreen extends ConsumerStatefulWidget {
  const AvatarPickerScreen({super.key});

  @override
  ConsumerState<AvatarPickerScreen> createState() => _AvatarPickerScreenState();
}

class _AvatarPickerScreenState extends ConsumerState<AvatarPickerScreen> {
  int? _selectedColor;   // 0=Red 1=Green 2=Yellow 3=Blue
  final _nameCtrl = TextEditingController();

  static const _colorNames  = ['Red',    'Green',  'Yellow', 'Blue'  ];
  static const _colorEmojis = ['🔴',     '🟢',     '🟡',     '🔵'   ];
  static const _colorLabels = ['♟ Red',  '♟ Green','♟ Yellow','♟ Blue'];

  @override
  void initState() {
    super.initState();
    // Pre-fill display name from user data
    final ud = ref.read(gameProvider).userData;
    _nameCtrl.text = ud?.displayName ?? 'Player';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _proceed() {
    if (_selectedColor == null) {
      showSnack(context, 'Pick a colour first!', color: Colors.orange.shade700);
      return;
    }
    final name = _nameCtrl.text.trim().isEmpty
        ? _colorNames[_selectedColor!]
        : _nameCtrl.text.trim();

    // Store the chosen colour index + display name in game state
    ref.read(gameProvider.notifier).setPlayerColor(_selectedColor!, name);

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LobbyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'Choose Your Token',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Instruction ────────────────────────────────────────
                    Text(
                      'Pick your colour token before joining a room.\nYou\'ll keep this colour throughout the game.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white60,
                            height: 1.5,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // ── Token grid (2×2 like Netflix profiles) ─────────────
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: List.generate(4, (i) {
                        final selected = _selectedColor == i;
                        return _TokenCard(
                          colorIndex: i,
                          label:      _colorLabels[i],
                          emoji:      _colorEmojis[i],
                          selected:   selected,
                          onTap:      () => setState(() => _selectedColor = i),
                        );
                      }),
                    ),

                    const SizedBox(height: 32),
                    const LabelDivider('YOUR DISPLAY NAME'),
                    const SizedBox(height: 12),

                    // ── Name field ─────────────────────────────────────────
                    TextField(
                      controller: _nameCtrl,
                      maxLength:  16,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText:    'Enter your name',
                        counterText: '',
                        prefixIcon:  _selectedColor != null
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  _colorEmojis[_selectedColor!],
                                  style: const TextStyle(fontSize: 18),
                                ),
                              )
                            : const Icon(Icons.person_outline,
                                color: Colors.white38),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Proceed button ─────────────────────────────────────
                    AnimatedOpacity(
                      opacity: _selectedColor != null ? 1.0 : 0.45,
                      duration: const Duration(milliseconds: 200),
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _selectedColor != null ? _proceed : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedColor != null
                                ? kPlayerColors[_selectedColor!]
                                : AppColors.violet,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_selectedColor != null) ...[
                                Text(_colorEmojis[_selectedColor!],
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 10),
                              ],
                              const Text('Continue to Lobby'),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_forward_ios_rounded,
                                  size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
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

// ── Token card ────────────────────────────────────────────────────────────────
class _TokenCard extends StatelessWidget {
  final int     colorIndex;
  final String  label;
  final String  emoji;
  final bool    selected;
  final VoidCallback onTap;

  const _TokenCard({
    required this.colorIndex,
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = kPlayerColors[colorIndex];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: selected
              ? color.withOpacity(0.22)
              : AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color:       color.withOpacity(0.35),
                    blurRadius:  16,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Token circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width:  selected ? 68 : 56,
              height: selected ? 68 : 56,
              decoration: BoxDecoration(
                color:  color,
                shape:  BoxShape.circle,
                border: Border.all(
                    color: Colors.white.withOpacity(selected ? 0.9 : 0.4),
                    width: selected ? 3 : 2),
                boxShadow: [
                  BoxShadow(
                    color:      color.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: selected ? 3 : 0,
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: Colors.white,
                  size: selected ? 28 : 22,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontSize:   14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:      selected ? color : Colors.white70,
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 4),
              Text('Selected ✓',
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      )
          .animate(target: selected ? 1 : 0)
          .scale(begin: const Offset(1,1), end: const Offset(1.03,1.03),
                 duration: 200.ms, curve: Curves.easeOut),
    );
  }
}
