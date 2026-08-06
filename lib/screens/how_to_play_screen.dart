// lib/screens/how_to_play_screen.dart
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: 'How to Play',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Section(
                      emoji: '🎯',
                      title: 'Goal',
                      body:
                          'Get all 4 of your tokens around the board and home before your opponents.',
                    ),
                    const SizedBox(height: 14),
                    const _Section(
                      emoji: '📋',
                      title: 'Basics',
                      bullets: [
                        'Take turns rolling the dice and moving a token forward.',
                        "Land on an opponent's token to send it back to their base — unless they're on a safe square.",
                        "Roll a 6 (or double-6 in Two-Dice Mode) to earn a bonus roll. Capturing an opponent also earns a bonus roll. Three 6's in a row without landing ends your turn.",
                        'First to bring all 4 tokens home wins!',
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _Section(
                      emoji: '🎮',
                      title: 'Modes',
                      bullets: [
                        'vs Bot: Race AI opponents — first to finish wins.',
                        'Multiplayer (local/online): Everyone plays it out to the end for full placements (1st–4th).',
                        'Two-Dice Mode: Roll two dice each turn and move two tokens independently for more strategic options.',
                      ],
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: "Got it, let's play!",
                      icon: Icons.check_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                      width: double.infinity,
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

class _Section extends StatelessWidget {
  final String emoji;
  final String title;
  final String? body;
  final List<String>? bullets;

  const _Section({
    required this.emoji,
    required this.title,
    this.body,
    this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          if (body != null)
            Text(body!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white70, height: 1.4)),
          if (bullets != null)
            ...bullets!.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      Expanded(
                        child: Text(b,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.white70, height: 1.4)),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
