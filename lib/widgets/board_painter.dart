// lib/widgets/board_painter.dart
// Uses CustomPainter so only dirty regions are redrawn.
// Token animations are handled by AnimatedPositioned in BoardWidget.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../theme/app_theme.dart';

class BoardPainter extends CustomPainter {
  final Map<int, List<List<int>>> tokens;
  final Set<int> highlightedPlayers;  // players with movable tokens
  final int? selectedToken;           // (player * 10 + tokenIdx)

  BoardPainter({
    required this.tokens,
    this.highlightedPlayers = const {},
    this.selectedToken,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width  / kBoardSize;
    final cellH = size.height / kBoardSize;

    final nestSets = [
      for (int i = 0; i < 4; i++)
        {for (final p in kNestPositions[i]) '${p[0]},${p[1]}'},
    ];
    final hpSets = [
      for (int i = 0; i < 4; i++)
        {for (final p in kHousePaths[i]) '${p[0]},${p[1]}'},
    ];
    final trackSet = {for (final p in kTrackPath) '${p[0]},${p[1]}'};

    for (int r = 0; r < kBoardSize; r++) {
      for (int c = 0; c < kBoardSize; c++) {
        final key = '$r,$c';
        final rect = Rect.fromLTWH(c * cellW, r * cellH, cellW - 0.6, cellH - 0.6);

        // Determine cell background
        Color bg = AppColors.surface;
        int? nestOwner;
        int? hpOwner;

        for (int i = 0; i < 4; i++) {
          if (nestSets[i].contains(key)) { nestOwner = i; break; }
        }
        if (nestOwner == null) {
          for (int i = 0; i < 4; i++) {
            if (hpSets[i].contains(key)) { hpOwner = i; break; }
          }
        }

        if (nestOwner != null) {
          bg = AppColors.nests[nestOwner];
        } else if (key == '${kFinalHome[0]},${kFinalHome[1]}') {
          bg = AppColors.boardHome;
        } else if (kSafeSquares.contains(key)) {
          bg = AppColors.boardSafe;
        } else if (hpOwner != null) {
          bg = AppColors.housePaths[hpOwner];
        } else if (trackSet.contains(key)) {
          bg = AppColors.boardTrack;
        } else {
          bg = AppColors.surface;
        }

        // Draw cell
        final paint = Paint()..color = bg;
        final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
        canvas.drawRRect(rRect, paint);

        // Border
        final borderPaint = Paint()
          ..color  = AppColors.border.withOpacity(0.6)
          ..style  = PaintingStyle.stroke
          ..strokeWidth = 0.4;
        canvas.drawRRect(rRect, borderPaint);

        // Safe star
        if (kSafeSquares.contains(key)) {
          _drawText(canvas, '★', rect, fontSize: cellW * 0.45, color: Colors.white70);
        }
        // Home
        if (key == '${kFinalHome[0]},${kFinalHome[1]}') {
          _drawText(canvas, '🏠', rect, fontSize: cellW * 0.5);
        }
        // Start markers
        for (int i = 0; i < 4; i++) {
          if (r == kStartPositions[i][0] && c == kStartPositions[i][1]) {
            final starPaint = Paint()
              ..color = AppColors.players[i]
              ..style = PaintingStyle.fill;
            canvas.drawCircle(rect.center, cellW * 0.28, starPaint);
          }
        }
        // Home column arrows
        if (hpOwner != null) {
          const arrows = ['↑', '→', '↓', '←'];
          _drawText(canvas, arrows[hpOwner], rect, fontSize: cellW * 0.35,
              color: AppColors.players[hpOwner].withOpacity(0.6));
        }
      }
    }

    // Draw tokens
    for (final entry in tokens.entries) {
      final player = entry.key;
      final toks   = entry.value;
      final posCount = <String, List<int>>{};
      for (int ti = 0; ti < toks.length; ti++) {
        final k = '${toks[ti][0]},${toks[ti][1]}';
        posCount.putIfAbsent(k, () => []);
        posCount[k]!.add(ti);
      }
      for (final posEntry in posCount.entries) {
        final parts = posEntry.key.split(',');
        final r = int.parse(parts[0]);
        final c = int.parse(parts[1]);
        final tokenList = posEntry.value;
        final rect = Rect.fromLTWH(c * cellW, r * cellH, cellW, cellH);
        _drawTokensAt(canvas, rect, player, tokenList, cellW);
      }
    }
  }

  void _drawTokensAt(Canvas canvas, Rect rect, int player, List<int> tis, double cellW) {
    final color = AppColors.players[player];
    final glow  = AppColors.glows[player];

    if (tis.length == 1) {
      final r = cellW * 0.32;
      final glowPaint = Paint()
        ..color      = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(rect.center, r + 2, glowPaint);

      final fill = Paint()..color = color;
      canvas.drawCircle(rect.center, r, fill);

      final border = Paint()
        ..color       = Colors.white
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(rect.center, r, border);

      _drawText(canvas, '${tis.first + 1}', rect,
          fontSize: cellW * 0.28, color: Colors.white, bold: true);
    } else {
      // Stacked tokens — draw small circles offset
      for (int k = 0; k < math.min(tis.length, 4); k++) {
        final offset = Offset(k * cellW * 0.15, k * cellW * 0.12);
        final center = rect.center + offset - Offset(cellW * 0.1, cellW * 0.1);
        final fill = Paint()..color = color;
        canvas.drawCircle(center, cellW * 0.2, fill);
        final border = Paint()
          ..color       = Colors.white
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawCircle(center, cellW * 0.2, border);
      }
    }
  }

  void _drawText(Canvas canvas, String text, Rect rect, {
    double fontSize = 10,
    Color color = Colors.white,
    bool bold = false,
  }) {
    final span = TextSpan(
      text: text,
      style: TextStyle(
        fontSize:   fontSize,
        color:      color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        height:     1,
      ),
    );
    final tp = TextPainter(
      text:      span,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        rect.left + (rect.width  - tp.width)  / 2,
        rect.top  + (rect.height - tp.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.tokens != tokens ||
      old.highlightedPlayers != highlightedPlayers ||
      old.selectedToken != selectedToken;
}
