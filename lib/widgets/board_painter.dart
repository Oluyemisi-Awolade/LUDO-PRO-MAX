// lib/widgets/board_painter.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../theme/app_theme.dart';

class BoardPainter extends CustomPainter {
  final Map<int, List<List<int>>> tokens;
  final int currentTurn;
  final bool diceRolled;
  final int playerIndex;

  BoardPainter({
    required this.tokens,
    required this.currentTurn,
    required this.diceRolled,
    required this.playerIndex,
  });

  // Arrow direction per track segment (row, col) → angle in radians
  static const Map<String, double> _arrowAngles = {
    // Red exit going right →
    '6,1': 0, '6,2': 0, '6,3': 0, '6,4': 0, '6,5': 0,
    // Turn up ↑
    '5,6': -math.pi/2, '4,6': -math.pi/2, '3,6': -math.pi/2,
    '2,6': -math.pi/2, '1,6': -math.pi/2, '0,6': -math.pi/2,
    // Turn right →
    '0,7': 0, '0,8': 0,
    // Green exit going down ↓
    '1,8': math.pi/2, '2,8': math.pi/2, '3,8': math.pi/2,
    '4,8': math.pi/2, '5,8': math.pi/2,
    // Turn right →
    '6,9': 0, '6,10': 0, '6,11': 0, '6,12': 0, '6,13': 0, '6,14': 0,
    // Turn down ↓
    '7,14': math.pi/2,
    // Yellow exit going left ←
    '8,14': math.pi, '8,13': math.pi, '8,12': math.pi, '8,11': math.pi,
    '8,10': math.pi, '8,9': math.pi,
    // Turn down ↓
    '9,8': math.pi/2, '10,8': math.pi/2, '11,8': math.pi/2,
    '12,8': math.pi/2, '13,8': math.pi/2, '14,8': math.pi/2,
    // Turn left ←
    '14,7': math.pi, '14,6': math.pi,
    // Blue exit going up ↑
    '13,6': -math.pi/2, '12,6': -math.pi/2, '11,6': -math.pi/2,
    '10,6': -math.pi/2, '9,6': -math.pi/2,
    // Turn left ←
    '8,5': math.pi, '8,4': math.pi, '8,3': math.pi,
    '8,2': math.pi, '8,1': math.pi, '8,0': math.pi,
    // Turn up ↑
    '7,0': -math.pi/2, '6,0': -math.pi/2,
  };

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
    final startSet = {
      for (int i = 0; i < 4; i++) '${kStartPositions[i][0]},${kStartPositions[i][1]}': i,
    };

    // Build token map
    final tok_map = <String, List<(int, int)>>{};
    for (final entry in tokens.entries) {
      for (int ti = 0; ti < entry.value.length; ti++) {
        final k = '${entry.value[ti][0]},${entry.value[ti][1]}';
        tok_map.putIfAbsent(k, () => []);
        tok_map[k]!.add((entry.key, ti));
      }
    }

    for (int r = 0; r < kBoardSize; r++) {
      for (int c = 0; c < kBoardSize; c++) {
        final key  = '$r,$c';
        final rect = Rect.fromLTWH(
            c * cellW + 0.3, r * cellH + 0.3, cellW - 0.6, cellH - 0.6);
        final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(2));

        // ── Cell colour ────────────────────────────────────────────────────
        Color bg = AppColors.surface;
        int?  nestOwner, hpOwner;

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
          // White cross sections (non-track, non-nest squares)
          bg = const Color(0xFF1A1A35);
        }

        // Start squares get the player colour
        final startIdx = startSet[key];
        if (startIdx != null) bg = AppColors.players[startIdx].withOpacity(0.85);

        canvas.drawRRect(rRect, Paint()..color = bg);

        // Border
        canvas.drawRRect(rRect,
            Paint()
              ..color       = AppColors.border.withOpacity(0.5)
              ..style       = PaintingStyle.stroke
              ..strokeWidth = 0.4);

        // ── Cell decorations ───────────────────────────────────────────────
        final cx = rect.left + rect.width  / 2;
        final cy = rect.top  + rect.height / 2;

        // Safe star
        if (kSafeSquares.contains(key)) {
          _drawStar(canvas, cx, cy, cellW * 0.28, Colors.white70);
        }

        // Home
        if (key == '${kFinalHome[0]},${kFinalHome[1]}') {
          _drawText(canvas, '🏠', rect, fontSize: cellW * 0.5);
        }

        // Track arrows
        if (trackSet.contains(key) && !kSafeSquares.contains(key) &&
            startIdx == null) {
          final angle = _arrowAngles[key];
          if (angle != null) {
            _drawArrow(canvas, cx, cy, cellW * 0.28, angle,
                Colors.white.withOpacity(0.35));
          }
        }

        // Home path arrows pointing toward centre
        if (hpOwner != null) {
          const inwardAngles = [0.0, math.pi/2, math.pi, -math.pi/2]; // R G Y B
          _drawArrow(canvas, cx, cy, cellW * 0.24, inwardAngles[hpOwner],
              AppColors.players[hpOwner].withOpacity(0.55));
        }

        // ── Tokens ─────────────────────────────────────────────────────────
        final here = tok_map[key];
        if (here != null && here.isNotEmpty) {
          _drawTokens(canvas, rect, here, cellW,
              highlight: diceRolled && here.any((t) => t.$1 == playerIndex));
        }
      }
    }
  }

  void _drawTokens(Canvas canvas, Rect rect,
      List<(int, int)> toks, double cellW, {bool highlight = false}) {
    if (toks.length == 1) {
      final (pi, ti) = toks.first;
      final color = AppColors.players[pi];
      final r     = cellW * 0.33;
      final cx    = rect.left + rect.width  / 2;
      final cy    = rect.top  + rect.height / 2;

      // Glow when tappable
      if (highlight) {
        canvas.drawCircle(Offset(cx, cy), r + 3,
            Paint()
              ..color      = color.withOpacity(0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      }
      // Shadow
      canvas.drawCircle(Offset(cx + 1.5, cy + 2), r,
          Paint()..color = Colors.black38);
      // Fill
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = color);
      // Border
      canvas.drawCircle(
          Offset(cx, cy), r,
          Paint()
            ..color       = Colors.white
            ..style       = PaintingStyle.stroke
            ..strokeWidth = 1.5);
      // Number
      _drawText(canvas, '${ti + 1}', rect,
          fontSize: cellW * 0.26, color: Colors.white, bold: true);
    } else {
      // Multiple tokens — small stacked circles
      for (int k = 0; k < math.min(toks.length, 4); k++) {
        final (pi, _) = toks[k];
        final color   = AppColors.players[pi];
        final ox      = k * cellW * 0.14 - toks.length * cellW * 0.07 + cellW * 0.07;
        final oy      = k * cellW * 0.1  - toks.length * cellW * 0.05 + cellW * 0.05;
        final cx      = rect.left + rect.width  / 2 + ox;
        final cy      = rect.top  + rect.height / 2 + oy;
        canvas.drawCircle(Offset(cx, cy), cellW * 0.2, Paint()..color = color);
        canvas.drawCircle(
            Offset(cx, cy), cellW * 0.2,
            Paint()
              ..color       = Colors.white
              ..style       = PaintingStyle.stroke
              ..strokeWidth = 1);
      }
    }
  }

  void _drawArrow(Canvas canvas, double cx, double cy,
      double size, double angle, Color color) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = 1.2
      ..style       = PaintingStyle.fill;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);

    final path = Path()
      ..moveTo(size, 0)
      ..lineTo(-size * 0.5,  size * 0.55)
      ..lineTo(-size * 0.5, -size * 0.55)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawStar(Canvas canvas, double cx, double cy,
      double r, Color color) {
    final paint = Paint()..color = color;
    final path  = Path();
    for (int i = 0; i < 10; i++) {
      final angle  = (i * math.pi / 5) - math.pi / 2;
      final radius = i.isEven ? r : r * 0.45;
      final x = cx + math.cos(angle) * radius;
      final y = cy + math.sin(angle) * radius;
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawText(Canvas canvas, String text, Rect rect,
      {double fontSize = 10, Color color = Colors.white, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              fontSize:   fontSize,
              color:      color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              height:     1)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset(rect.left + (rect.width  - tp.width)  / 2,
               rect.top  + (rect.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.tokens != tokens ||
      old.currentTurn != currentTurn ||
      old.diceRolled != diceRolled;
}
