// lib/widgets/dice_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

// Dice face characters — defined locally so no dependency on constants.dart
const Map<int, String> _diceEmoji = {
  0: '⚀', 1: '⚀', 2: '⚁', 3: '⚂', 4: '⚃', 5: '⚄', 6: '⚅',
};

class DiceWidget extends StatelessWidget {
  final int  value;
  final bool rolling;

  const DiceWidget({super.key, required this.value, this.rolling = false});

  @override
  Widget build(BuildContext context) {
    final face = _diceEmoji[value] ?? '⚀';
    Widget die = Container(
      width: 54, height: 54,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.violet, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withOpacity(0.3),
            blurRadius: 8, spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: Text(face, style: const TextStyle(fontSize: 32)),
      ),
    );

    if (rolling) {
      die = die
          .animate(onPlay: (c) => c.repeat())
          .shake(duration: 120.ms, hz: 8, rotation: 0.05);
    } else if (value > 0) {
      die = die
          .animate()
          .scale(
              begin: const Offset(0.7, 0.7),
              duration: 200.ms,
              curve: Curves.elasticOut)
          .fadeIn(duration: 150.ms);
    }

    return die;
  }
}

class RollButton extends StatelessWidget {
  final String    label;
  final bool      enabled;
  final VoidCallback? onPressed;
  final Color?    color;

  const RollButton({
    super.key,
    required this.label,
    required this.enabled,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.violet;
    return AnimatedOpacity(
      opacity: enabled ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: ElevatedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: const Icon(Icons.casino_rounded, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          disabledBackgroundColor: bg.withOpacity(0.5),
          disabledForegroundColor: Colors.white54,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(
              horizontal: 20, vertical: 14),
          elevation: enabled ? 3 : 0,
        ),
      ),
    );
  }
}
